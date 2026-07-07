import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/profile/providers/provider_type_provider.dart';
import '../di/providers.dart';
import 'provider_status_provider.dart';

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

// Window slightly under the 4 s heartbeat: long enough to absorb a
// kick-once that fires microseconds after a periodic tick, short enough
// that the next periodic tick is never accidentally suppressed.
const Duration _kOnlineLocationPostMinGap = Duration(seconds: 3);

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
///   - goOffline(): POST `status:'offline'` with last-known coords, then
///     flip local state so the UI reflects the intent immediately. Even if
///     the POST fails, local state still flips — otherwise the user is
///     stuck online on flaky networks.
///
/// Rationale: previously the app only signalled "offline" via the socket
/// disconnect, leaving the backend to infer offline via a location TTL.
/// That meant a freshly-toggled-off driver/artisan could still receive
/// dispatches for minutes. Explicit offline POST closes that window.
class AvailabilityController {
  AvailabilityController(this._ref);

  final Ref _ref;

  /// Flip to online. Verifies location services + permission first because
  /// an online provider without a GPS fix is invisible to the matcher
  /// (the backend requires `current_location IS NOT NULL`). POSTs the
  /// online status to the backend before flipping local state so the
  /// matcher includes this provider on the very next request.
  ///
  /// Returns `null` on success, or a user-facing error message on failure.
  Future<String?> goOnline() async {
    final gate = await _checkLocationReady();
    if (gate != null) return gate;

    // Need a fix to send with the online POST — backend requires
    // current_location to be non-null before it'll mark us online.
    Position position;
    final cached = _ref.read(lastKnownPositionProvider);
    if (cached != null) {
      position = cached;
    } else {
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        _ref.read(lastKnownPositionProvider.notifier).state = position;
      } catch (e) {
        debugPrint('[Availability] online: position fetch failed — $e');
        return "Couldn't get your location. Check signal and try again.";
      }
    }

    final isArtisan = _ref.read(providerTypeProvider).isArtisan;
    final locationService = _ref.read(locationServiceProvider);
    try {
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          status: 'online',
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          status: 'online',
        );
      }
      // Seed the dedup so the bridge's kick-once POST (which fires the
      // moment we flip providerStatusProvider below) is suppressed.
      markOnlineLocationPosted();
      debugPrint('[Availability] online POST sent');
    } on ApiException catch (e) {
      debugPrint('[Availability] online POST failed: $e');
      return e.message.isNotEmpty
          ? e.message
          : "Couldn't reach the server. Check your connection and try again.";
    } catch (e) {
      debugPrint('[Availability] online POST error: $e');
      return "Couldn't reach the server. Check your connection and try again.";
    }

    _ref.read(providerStatusProvider.notifier).goOnline();
    return null;
  }

  /// Verify location services are on and permission is granted. Requests
  /// permission if it hasn't been asked yet. Returns a user-facing error
  /// message if location can't be used, `null` if all good.
  Future<String?> _checkLocationReady() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
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
  Future<void> refreshHeartbeat() async {
    if (_ref.read(providerStatusProvider).isOffline) return;
    final pos = _ref.read(lastKnownPositionProvider);
    if (pos == null) return;

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
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'online',
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'online',
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

  /// Force the provider offline without a user gesture — used by the
  /// location-permission watcher when the OS revokes permission or
  /// services are disabled mid-session.
  Future<void> forceOfflineDueToLocationLost() async {
    if (_ref.read(providerStatusProvider).isOffline) return;
    debugPrint('[Availability] forcing offline: location unavailable');
    await goOffline();
  }

  /// Flip to offline and inform the backend so the matcher stops
  /// dispatching. Local state flips immediately; the backend call is
  /// best-effort.
  Future<void> goOffline() async {
    _ref.read(providerStatusProvider.notifier).goOffline();
    // Reset the online-POST dedup so a rapid offline→online flip
    // always resends. Done here (not in _postOffline) so it runs even
    // when there's no cached position to POST with.
    clearOnlineLocationPostAt();
    await _postOffline();
  }

  Future<void> _postOffline() async {
    final pos = _ref.read(lastKnownPositionProvider);
    if (pos == null) {
      // No cached fix — can't satisfy the current endpoint's required
      // lat/lng. Safe to skip: the device never successfully went online
      // from the backend's perspective either.
      debugPrint('[Availability] no cached position — skipping offline POST');
      return;
    }

    final isArtisan = _ref.read(providerTypeProvider).isArtisan;
    final locationService = _ref.read(locationServiceProvider);
    try {
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'offline',
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'offline',
        );
      }
      debugPrint('[Availability] offline POST sent');
    } on ApiException catch (e) {
      debugPrint('[Availability] offline POST failed: $e');
    } catch (e) {
      debugPrint('[Availability] offline POST error: $e');
    }
  }
}

final availabilityControllerProvider = Provider<AvailabilityController>((ref) {
  return AvailabilityController(ref);
});
