import 'dart:async';
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:incoming_request_overlay/incoming_request_overlay.dart';

import '../../features/profile/providers/provider_type_provider.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../di/providers.dart';
import '../services/ios_always_location_permission_bridge.dart';
import '../services/fcm_service.dart';
import 'provider_status_provider.dart';
import 'availability_reconciliation_controller.dart';
import 'location_degradation_provider.dart';
import 'provider_location_session_provider.dart';
import 'provider_online_intent.dart';

/// Last known GPS fix — populated by the location bridge whenever a fix
/// arrives. Used so the offline-toggle POST can include coordinates even
/// after the location stream has been torn down.
///
/// TODO(backend-B1): once POST /providers/availability ships, coords are
/// no longer required and this cache can be retired.
final lastKnownPositionProvider = StateProvider<Position?>((_) => null);

// Tracks the last successful `status:'online'` POST so the heartbeat,
// bridge kick-once, refreshHeartbeat, and goOnline don't all pile on
// top of each other and trip the global IP throttler. File-scope so it
// survives bridge re-evaluations (status flips, socket reconnects).
DateTime? _lastOnlineLocationPostAt;
bool _overlayPermissionPromptedThisRun = false;

// Window slightly under the 4 s heartbeat: long enough to absorb a
// kick-once that fires microseconds after a periodic tick, short enough
// that the next periodic tick is never accidentally suppressed.
const Duration _kOnlineLocationPostMinGap = Duration(seconds: 3);

/// Approved BR-30 authority for a fix used to enter the matching pool.
const Duration onlineLocationMaxAge = Duration(seconds: 30);
const double onlineLocationMaxAccuracyMeters = 50;

/// Converts the backend availability contract into stable, actionable copy.
///
/// Do not surface arbitrary server/provider text here. Go Online is a critical
/// path and older deployments have returned internal or misleading messages;
/// known machine codes are the authority and unknown failures stay generic.
String friendlyAvailabilityApiError(ApiException error) {
  if (error.errorCode == 'PROVIDER_NOT_ELIGIBLE') {
    return _providerEligibilityErrorCopy(error.details?['reasonCodes']);
  }

  switch (error.errorCode) {
    case 'NOT_VERIFIED':
      return 'The server could not confirm that this provider profile is '
          'eligible to go online. Refresh Documents & Verification. If every '
          'item is approved, contact support.';
    case 'ACCOUNT_SUSPENDED':
      return 'This provider profile is suspended. Review your notice or '
          'contact support.';
    case 'NOTIFICATION_REACHABILITY_REQUIRED':
      return 'Enable notifications in Settings and try again so you can '
          'receive requests.';
    case 'OUTSIDE_PILOT_REGION':
      return "You're outside MyShop's current service area. Move inside the "
          'active area and try again.';
    case 'GPS_REQUIRED':
    case 'NO_LOCATION_SAMPLES':
      return 'A fresh location is required. Turn on Location Services, wait '
          'for GPS to settle, and try again.';
    case 'GPS_FIX_STALE':
      return 'Your location fix is out of date. Keep Location Services on, '
          'wait for a new GPS fix, and try again.';
    case 'GPS_FIX_OUT_OF_ORDER':
      return 'A newer location is already saved. Wait for the next GPS fix '
          'and try again.';
    case 'GPS_SAMPLE_SEQUENCE_INVALID':
    case 'PROVIDER_LOCATION_SESSION_REQUIRED':
    case 'DRIVER_ONLINE_SESSION_REQUIRED':
    case 'ARTISAN_ONLINE_SESSION_REQUIRED':
      return 'Your previous Online session ended. Go offline, then go online '
          'again before sending location.';
    case 'GPS_ACCURACY_REQUIRED':
      return 'GPS accuracy is too low. Move to an open area, wait for the '
          'location signal to improve, and try again.';
    case 'RATE_LIMIT_EXCEEDED':
      return 'Location was updated too quickly. Wait a few seconds and try '
          'again.';
    case 'DRIVER_PROFILE_REQUIRED':
      return "We couldn't find your driver profile. Sign out and back in. If "
          'it still fails, contact support.';
    case 'ARTISAN_PROFILE_REQUIRED':
      return "We couldn't find your artisan profile. Sign out and back in. If "
          'it still fails, contact support.';
    case 'PROVIDER_ROLE_REQUIRED':
    case 'INVALID_ROLE':
    case 'ROLE_MISMATCH':
      return 'Your provider session does not match this profile. Sign out and '
          'back in, then try again.';
    case 'TOGGLE_LOCKED_ACTIVE_RIDE':
      return "You can't go offline while a ride is active.";
    case 'TOGGLE_LOCKED_ACTIVE_JOB':
      return "You can't go offline while a job is active.";
    case 'APP_UPDATE_REQUIRED':
      return 'Update MyShop before going online.';
  }

  if (error.isNetworkError) {
    return 'No connection to MyShop. Check your network and try again.';
  }
  if (error.isServerError) {
    return "MyShop couldn't complete the Go Online request. Try again shortly.";
  }
  return "We couldn't change your availability. Try again. If it continues, "
      'contact support.';
}

String _providerEligibilityErrorCopy(Object? rawReasonCodes) {
  final codes = rawReasonCodes is List
      ? rawReasonCodes.whereType<String>().toSet()
      : const <String>{};

  if (codes.contains('ROLE_ACCOUNT_NOT_ACTIVE')) {
    return 'This provider account is not active. Review your account notice or '
        'contact support.';
  }
  if (codes.contains('RM_FINAL_APPROVAL_REQUIRED') ||
      codes.contains('PROVIDER_APPROVAL_REQUIRED')) {
    return 'Regional Manager approval is required before you can go online. '
        'Check Documents & Verification for the current status.';
  }
  if (codes.contains('VEHICLE_SELECTION_REQUIRED')) {
    return 'Select the approved vehicle you are using before going online.';
  }
  if (codes.contains('ACTIVE_VEHICLE_CHANGE_REQUIRES_OFFLINE')) {
    return 'Go offline before changing your selected vehicle.';
  }
  if (codes.contains('LEGACY_VEHICLE_BACKFILL_REQUIRED')) {
    return 'Support must update your existing vehicle record before it can be '
        'used online.';
  }
  if (codes.contains('VEHICLE_NOT_AVAILABLE')) {
    return 'The selected vehicle is unavailable. Choose another approved '
        'vehicle or contact support.';
  }
  if (codes.contains('VEHICLE_RIDE_CATEGORY_NOT_APPROVED')) {
    return 'The selected vehicle needs an approved ride category before it can '
        'be used online.';
  }
  if (codes.contains('DOCUMENT_EXPIRED_DRIVERS_LICENCE')) {
    return "Your driver's licence has expired. Upload the renewed document for "
        'approval before going online.';
  }
  if (codes.contains('VEHICLE_DOCUMENT_EXPIRED_ROADWORTHINESS')) {
    return 'The selected vehicle’s roadworthiness certificate has expired. '
        'Upload the renewed certificate for approval.';
  }
  if (codes.contains('VEHICLE_DOCUMENT_EXPIRED_INSURANCE')) {
    return 'The selected vehicle’s insurance certificate has expired. Upload '
        'the renewed certificate for approval.';
  }
  if (codes.contains('VEHICLE_DOCUMENT_EXPIRY_MISSING_ROADWORTHINESS')) {
    return 'The selected vehicle’s roadworthiness expiry date is missing. '
        'Contact support to add the date printed on the certificate.';
  }
  if (codes.contains('VEHICLE_DOCUMENT_EXPIRY_MISSING_INSURANCE')) {
    return 'The selected vehicle’s insurance expiry date is missing. Contact '
        'support to add the date printed on the certificate.';
  }
  if (codes.any((code) => code.contains('ROADWORTHINESS'))) {
    return 'The selected vehicle needs a current, independently approved '
        'roadworthiness certificate.';
  }
  if (codes.any((code) => code.contains('INSURANCE'))) {
    return 'The selected vehicle needs a current, independently approved '
        'insurance certificate.';
  }
  if (codes.any((code) => code.contains('DRIVERS_LICENCE'))) {
    return "A current, independently approved driver's licence is required.";
  }
  if (codes.any((code) => code.contains('GHANA_CARD'))) {
    return 'An independently approved Ghana Card is required before you can go '
        'online.';
  }
  if (codes.any((code) => code.contains('PROFILE_PHOTO'))) {
    return 'An independently approved profile picture is required before you '
        'can go online.';
  }
  if (codes.contains('ARTISAN_TRADE_CREDENTIAL_XOR_CONFLICT')) {
    return 'Business Registration and Trade Certificate cannot both be active. '
        'Contact support to correct the verification record.';
  }
  if (codes.contains('ARTISAN_TRADE_CREDENTIAL_MISSING') ||
      codes.contains('ARTISAN_TRADE_CREDENTIAL_NOT_APPROVED')) {
    return 'An independently approved Business Registration or Trade '
        'Certificate is required before you can go online.';
  }
  if (codes.contains('DOCUMENT_REPLACEMENT_GRACE_EXPIRED')) {
    return 'A document replacement grace period has ended. Open Documents & '
        'Verification to complete the required approval.';
  }
  if (codes.contains('OFFER_RECEIPT_CAPABILITY_REQUIRED')) {
    return 'Notification delivery is not ready for requests. Check '
        'Notifications in Settings, reopen the app, and try again.';
  }
  if (codes.contains('LOCATION_DEGRADED')) {
    return 'Location tracking must recover before you can receive new '
        'requests. Check Location Services and try Go Online again.';
  }
  if (codes.contains('GPS_REQUIRED') || codes.contains('GPS_LOCATION_STALE')) {
    return 'A fresh location is required. Turn on Location Services, wait for '
        'a new GPS fix, and try again.';
  }
  if (codes.contains('GPS_ACCURACY_INSUFFICIENT')) {
    return 'GPS accuracy is too low. Move to an open area, wait for the signal '
        'to improve, and try again.';
  }
  if (codes.contains('DRIVER_ONLINE_SESSION_REQUIRED') ||
      codes.contains('ARTISAN_ONLINE_SESSION_REQUIRED')) {
    return 'Your previous Online session ended. Tap Go Online to start a fresh '
        'session.';
  }

  return 'The server could not confirm every requirement for this provider '
      'account. Review Documents & Verification and your selected vehicle, '
      'then try again.';
}

bool isOnlineLocationFixAcceptable(
  Position position, {
  DateTime? now,
}) {
  final latitude = position.latitude;
  final longitude = position.longitude;
  final accuracy = position.accuracy;
  if (!latitude.isFinite || latitude < -90 || latitude > 90) return false;
  if (!longitude.isFinite || longitude < -180 || longitude > 180) {
    return false;
  }
  if (!accuracy.isFinite ||
      accuracy < 0 ||
      accuracy > onlineLocationMaxAccuracyMeters) {
    return false;
  }

  final age = (now ?? DateTime.now()).difference(position.timestamp);
  return !age.isNegative && age <= onlineLocationMaxAge;
}

/// True when an online location POST should be suppressed because we
/// just sent one. Offline POSTs (status:'offline') always bypass this.
bool shouldSkipOnlineLocationPost() {
  final last = _lastOnlineLocationPostAt;
  if (last == null) return false;
  return DateTime.now().difference(last) < _kOnlineLocationPostMinGap;
}

/// Record a successful online POST. Subsequent online POSTs within the
/// dedup window are skipped via [shouldSkipOnlineLocationPost].
void markOnlineLocationPosted() {
  _lastOnlineLocationPostAt = DateTime.now();
}

/// Reset the dedup so the very next online POST always goes through.
/// Called after an offline transition so a rapid offline→online flip
/// doesn't leave the matcher with a stale "you just posted" guard.
void clearOnlineLocationPostAt() {
  _lastOnlineLocationPostAt = null;
}

/// Orchestrates the online/offline transition for the provider:
///
///   - goOnline(): verify location → fetch a fix → POST
///     `/location/{driver,artisan}/update` with status:'online' → flip
///     local state. Posting before the flip closes a race where the
///     socket bridge's first heartbeat lagged the local toggle by a few
///     seconds, leaving the artisan locally-online but invisible to the
///     matcher. Jobs created in that window were silently missed.
///   - goOffline(): POST `status:'offline'` to the authoritative no-GPS
///     availability endpoint, which also
///     clears the selected vehicle. Local state changes only after success so
///     an active-work rejection or network failure cannot falsely show offline.
///
/// Rationale: previously the app only signalled "offline" via the socket
/// disconnect, leaving the backend to infer offline via a location TTL.
/// That meant a freshly-toggled-off driver/artisan could still receive
/// dispatches for minutes. Explicit offline POST closes that window.
class AvailabilityController {
  AvailabilityController(this._ref);

  final Ref _ref;
  Future<String?>? _goOnlineInFlight;
  Future<String?>? _goOfflineInFlight;
  Future<void>? _heartbeatRefreshInFlight;

  /// Flip to online. Verifies location services + permission first because
  /// an online provider without a GPS fix is invisible to the matcher
  /// (the backend requires `current_location IS NOT NULL`). POSTs the
  /// online status to the backend before flipping local state so the
  /// matcher includes this provider on the very next request.
  ///
  /// Returns `null` on success, or a user-facing error message on failure.
  Future<String?> goOnline({
    required bool backgroundLocationDisclosureAccepted,
    String? vehicleId,
  }) {
    _ref.read(systemTelemetryProvider).trackAction(
      'provider_go_online_requested',
      metadata: {'vehicleSelected': vehicleId != null},
    );
    // Keep the sensitive iOS Always request coupled to the provider's explicit
    // Go Online action and the disclosure immediately preceding it. This also
    // prevents future startup/reconciliation callers from triggering the OS
    // prompt accidentally.
    if (!backgroundLocationDisclosureAccepted) {
      return Future<String?>.value(
        'Review and accept the background location disclosure to go online.',
      );
    }

    _ref.read(availabilityRestoreNoticeProvider.notifier).state = null;

    final status = _ref.read(providerStatusProvider);
    if (!status.isOffline) {
      debugPrint('[Availability] online requested while status=$status — noop');
      return Future<String?>.value(null);
    }

    final inFlight = _goOnlineInFlight;
    if (inFlight != null) {
      debugPrint('[Availability] online request already in flight — joining');
      return inFlight;
    }

    final future = _goOnline(
      vehicleId: vehicleId,
      allowPermissionPrompts: true,
      promptOverlayPermission: true,
    ).whenComplete(() {
      _goOnlineInFlight = null;
    });
    _goOnlineInFlight = future;
    return future;
  }

  /// Attempts BR-32 process-relaunch restoration from a previously persisted
  /// exact-role Online intent. This path deliberately cannot show notification,
  /// location, iOS Always, or Android overlay permission prompts. Existing
  /// grants plus a fresh device fix must already satisfy every gate; otherwise
  /// the reconciliation controller keeps the role Offline with visible copy.
  Future<String?> restorePriorOnlineIntent({String? vehicleId}) {
    final status = _ref.read(providerStatusProvider);
    if (!status.isOffline) return Future<String?>.value(null);

    final inFlight = _goOnlineInFlight;
    if (inFlight != null) return inFlight;

    final future = _goOnline(
      vehicleId: vehicleId,
      allowPermissionPrompts: false,
      promptOverlayPermission: false,
    ).whenComplete(() {
      _goOnlineInFlight = null;
    });
    _goOnlineInFlight = future;
    return future;
  }

  Future<String?> _goOnline({
    String? vehicleId,
    required bool allowPermissionPrompts,
    required bool promptOverlayPermission,
  }) async {
    final notificationGate = await _ref.read(
      allowPermissionPrompts
          ? onlineNotificationReachabilityCheckProvider
          : onlineNotificationRestoreReachabilityCheckProvider,
    )();
    if (notificationGate != null) return notificationGate;

    final gate = await _checkLocationReady(
      allowPermissionPrompts: allowPermissionPrompts,
    );
    if (gate != null) return gate;

    // Need a fix to send with the online POST — backend requires
    // current_location to be non-null before it'll mark us online.
    Position position;
    try {
      position = await resolveOnlineEntryPosition(
        _ref.read(lastKnownPositionProvider),
        lastKnownLoader: _ref.read(lastKnownPositionLoaderProvider),
        currentLoader: _ref.read(onlineEntryPositionLoaderProvider),
      );
      _ref.read(lastKnownPositionProvider.notifier).state = position;
    } catch (e) {
      debugPrint('[Availability] online: position fetch failed — $e');
      if (e is TimeoutException) {
        return 'GPS could not get an accurate fix within '
            '${onlineEntryFixTimeout.inSeconds} seconds. Move near a window '
            'or outdoors, keep Location Services on, and try again.';
      }
      return "Couldn't get your location. Keep Location Services on and try "
          'again.';
    }

    if (!isOnlineLocationFixAcceptable(position)) {
      return 'Your location is not accurate or recent enough to go online. '
          'Move to an open area, wait for GPS to settle, and try again.';
    }

    final isArtisan = _ref.read(providerTypeProvider).isArtisan;
    final locationService = _ref.read(locationServiceProvider);
    try {
      final locationSession = _ref.read(providerLocationSessionProvider);
      final sampleSequence = locationSession == null
          ? null
          : _ref.read(providerLocationSessionProvider.notifier).nextSequence();
      final Map<String, dynamic> response;
      if (isArtisan) {
        response = await locationService.updateArtisanLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          recordedAt: position.timestamp,
          status: 'online',
          onlineSessionId: locationSession?.onlineSessionId,
          sampleSequence: sampleSequence,
        );
      } else {
        response = await locationService.updateDriverLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          recordedAt: position.timestamp,
          vehicleId: vehicleId,
          status: 'online',
          onlineSessionId: locationSession?.onlineSessionId,
          sampleSequence: sampleSequence,
        );
      }
      _ref
          .read(providerLocationSessionProvider.notifier)
          .installResponse(response);
      // Seed the dedup so the bridge's kick-once POST (which fires the
      // moment we flip providerStatusProvider below) is suppressed.
      markOnlineLocationPosted();
      debugPrint('[Availability] online POST sent');
    } on ApiException catch (e) {
      debugPrint('[Availability] online POST failed: $e');
      return friendlyAvailabilityApiError(e);
    } catch (e) {
      debugPrint('[Availability] online POST error: $e');
      return "Couldn't reach the server. Check your connection and try again.";
    }

    await _writeOnlineIntent(shouldBeOnline: true);
    _ref.read(providerStatusProvider.notifier).goOnline();
    if (promptOverlayPermission &&
        Platform.isAndroid &&
        !_overlayPermissionPromptedThisRun) {
      _overlayPermissionPromptedThisRun = true;
      unawaited(_promptForOverlayPermissionIfNeeded());
    }
    return null;
  }

  Future<void> _promptForOverlayPermissionIfNeeded() async {
    try {
      final overlay = IncomingRequestOverlay.instance;
      if (!await overlay.isSupported() || await overlay.canDrawOverlays()) {
        return;
      }
      // This follows an explicit "go online" gesture: the provider is asking
      // to receive work, so this is the least surprising moment to explain and
      // request the special Android access. Notification Settings remains the
      // retry path if they decline.
      await overlay.openOverlaySettings();
    } catch (error) {
      debugPrint('[Availability] overlay permission prompt failed: $error');
    }
  }

  /// Verify location services are on and permission is granted. Requests
  /// permission if it hasn't been asked yet. Returns a user-facing error
  /// message if location can't be used, `null` if all good.
  Future<String?> _checkLocationReady({
    required bool allowPermissionPrompts,
  }) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && allowPermissionPrompts) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse &&
          allowPermissionPrompts) {
        if (Platform.isIOS) {
          // geolocator_apple does not elevate an existing When In Use grant.
          // Invoke Core Location's second-stage request, then re-read the
          // plugin's authoritative state. iOS may keep While In Use, in which
          // case the caller presents the Settings recovery path.
          await _ref
              .read(iosAlwaysLocationPermissionBridgeProvider)
              .requestAlwaysAuthorization();
          permission = await Geolocator.checkPermission();
        } else {
          // Preserve Android's existing flow. Android 11+ may still require
          // the user to select Allow all the time in system Settings.
          permission = await Geolocator.requestPermission();
        }
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'Location permission is required to go online. '
            'Grant it in Settings and try again.';
      }
      if (permission != LocationPermission.always) {
        return 'Set Location permission to Always / Allow all the time '
            'so MyShop can keep you online when the screen is off.';
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return 'Turn on Location Services to go online.';
      }
    } catch (error) {
      debugPrint('[Availability] location readiness check failed: $error');
      return "Couldn't check location access. Restart the app and try again.";
    }
    return null;
  }

  /// Refresh the backend's liveness heartbeat without flipping local
  /// state. Called as the app moves to background — once the foreground
  /// is gone, the socket bridge's 4s heartbeat stops firing (iOS suspend,
  /// Android Doze), and the backend's 5-min Redis TTL ticks down from
  /// whatever the last heartbeat was. The matcher's SQL gates on
  /// `online_status = 'online'`, which the zombie-offline cron flips
  /// off the moment the heartbeat key expires — so a backgrounded
  /// provider with a stale heartbeat silently misses inbound jobs even
  /// though FCM would have woken them. Refreshing here resets the TTL
  /// to a full window. Fire-and-forget; failures don't roll back local
  /// state — the user is leaving foreground anyway.
  Future<void> refreshHeartbeat() {
    final inFlight = _heartbeatRefreshInFlight;
    if (inFlight != null) {
      debugPrint(
          '[Availability] heartbeat refresh already in flight — joining');
      return inFlight;
    }

    final future = _refreshHeartbeat().whenComplete(() {
      _heartbeatRefreshInFlight = null;
    });
    _heartbeatRefreshInFlight = future;
    return future;
  }

  Future<void> _refreshHeartbeat() async {
    if (_ref.read(providerStatusProvider).isOffline) return;
    Position pos;
    try {
      pos = await resolvePeriodicOnlinePosition(
        _ref.read(lastKnownPositionProvider),
        loader: _ref.read(onlinePositionLoaderProvider),
      );
    } catch (error) {
      debugPrint(
        '[Availability] heartbeat refresh fresh-fix request failed: $error',
      );
      return;
    }
    if (periodicOnlineFixRefreshRequired(pos) ||
        !isOnlineLocationFixAcceptable(pos)) {
      debugPrint(
        '[Availability] heartbeat refresh skipped — fresh fix unusable',
      );
      return;
    }
    _ref.read(lastKnownPositionProvider.notifier).state = pos;

    // The 4 s socket-bridge heartbeat may have just fired; if so the
    // backend Redis TTL was already extended and posting again here
    // only spends rate-limit budget. Skip — the periodic tick we just
    // observed already did this work.
    if (shouldSkipOnlineLocationPost()) {
      debugPrint('[Availability] heartbeat refresh skipped — recent POST');
      return;
    }

    final isArtisan = _ref.read(providerTypeProvider).isArtisan;
    final locationService = _ref.read(locationServiceProvider);
    try {
      final locationSession = _ref.read(providerLocationSessionProvider);
      if (locationSession == null) {
        debugPrint(
            '[Availability] heartbeat refresh skipped — no location epoch');
        return;
      }
      final sampleSequence =
          _ref.read(providerLocationSessionProvider.notifier).nextSequence();
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
          recordedAt: pos.timestamp,
          status: 'online',
          onlineSessionId: locationSession.onlineSessionId,
          sampleSequence: sampleSequence,
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
          recordedAt: pos.timestamp,
          status: 'online',
          onlineSessionId: locationSession.onlineSessionId,
          sampleSequence: sampleSequence,
        );
      }
      markOnlineLocationPosted();
      debugPrint('[Availability] heartbeat refreshed for backgrounding');
    } on ApiException catch (e) {
      debugPrint('[Availability] heartbeat refresh failed: $e');
    } catch (e) {
      debugPrint('[Availability] heartbeat refresh error: $e');
    }
  }

  /// Report device-authoritative location loss. The backend keeps active work
  /// alive, removes all new-dispatch authority, and forces an idle provider
  /// Offline. Local degraded state is immediate so a network outage cannot
  /// hide the safety warning while the server's stale-fix detector catches up.
  Future<void> reportLocationUnavailable(
    LocationUnavailableReason reason,
  ) async {
    if (_ref.read(providerStatusProvider).isOffline) return;
    final status = _ref.read(providerStatusProvider);
    _ref.read(providerLocationDegradationProvider.notifier).state =
        ProviderLocationDegradationState.local(
      reason: reason,
      hasActiveWork: status.isBusy,
    );
    debugPrint('[Availability] reporting location unavailable');
    try {
      await _ref.read(locationServiceProvider).reportUnavailable(reason);
      await _ref
          .read(availabilityReconciliationControllerProvider)
          .reconcile(trigger: 'location_unavailable_report');
    } on ApiException catch (error) {
      debugPrint(
        '[Availability] location-unavailable report failed: '
        '${error.errorCode ?? error.message}',
      );
    } catch (error) {
      debugPrint('[Availability] location-unavailable report error: $error');
    }
  }

  Future<void> forceOfflineDueToLocationLost() =>
      reportLocationUnavailable(LocationUnavailableReason.gpsUnavailable);

  /// Ask the backend to close the online session without depending on a GPS
  /// fix. For drivers, the same transaction clears activeVehicleId so every
  /// later Go Online requires a fresh explicit vehicle selection.
  Future<String?> goOffline() {
    _ref
        .read(systemTelemetryProvider)
        .trackAction('provider_go_offline_requested');
    final inFlight = _goOfflineInFlight;
    if (inFlight != null) return inFlight;

    final future = _goOffline().whenComplete(() {
      _goOfflineInFlight = null;
    });
    _goOfflineInFlight = future;
    return future;
  }

  Future<String?> _goOffline() async {
    try {
      await _ref.read(providerAvailabilityServiceProvider).setMyAvailability(
            status: ProviderAvailabilityStatus.offline,
          );
      await _writeOnlineIntent(shouldBeOnline: false);
      _ref.read(providerStatusProvider.notifier).goOffline();
      _ref.read(providerLocationSessionProvider.notifier).clear();
      _ref.read(availabilityRestoreNoticeProvider.notifier).state = null;
      clearOnlineLocationPostAt();
      debugPrint('[Availability] authoritative offline confirmed');
      return null;
    } on ApiException catch (e) {
      debugPrint('[Availability] offline POST failed: $e');
      return friendlyAvailabilityApiError(e);
    } catch (e) {
      debugPrint('[Availability] offline POST error: $e');
      return "Couldn't reach the server. Check your connection and try again.";
    }
  }

  Future<void> _writeOnlineIntent({required bool shouldBeOnline}) async {
    try {
      final identity = _ref.read(currentProviderOnlineIntentIdentityProvider);
      if (identity == null) return;
      await _ref.read(providerOnlineIntentStoreProvider).write(
            identity,
            shouldBeOnline: shouldBeOnline,
          );
    } catch (error) {
      // Storage failure must never claim an Online transition failed after the
      // server accepted it. The safe consequence is simply no auto-restore on
      // the next process launch.
      debugPrint('[Availability] Online intent persistence failed: $error');
    }
  }
}

@visibleForTesting
Future<Position> resolveOnlineEntryPosition(
  Position? cached, {
  required LastKnownPositionLoader lastKnownLoader,
  required OnlinePositionLoader currentLoader,
  DateTime? now,
}) async {
  if (cached != null && isOnlineLocationFixAcceptable(cached, now: now)) {
    return cached;
  }

  try {
    final lastKnown = await lastKnownLoader();
    if (lastKnown != null &&
        isOnlineLocationFixAcceptable(lastKnown, now: now)) {
      return lastKnown;
    }
  } catch (error) {
    debugPrint('[Availability] last-known position fetch failed — $error');
  }

  return currentLoader();
}

final availabilityControllerProvider = Provider<AvailabilityController>((ref) {
  return AvailabilityController(ref);
});
