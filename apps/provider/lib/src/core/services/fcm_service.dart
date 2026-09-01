import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart'
    show ApiException, AppCallSession, AuthSessionIdentity;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../app/router.dart';
import '../../features/artisan_home/providers/active_job_provider.dart';
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_home/widgets/rate_client_sheet.dart';
import '../../features/artisan_home/widgets/bid_status_banner.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../../features/driver_home/widgets/rate_passenger_sheet.dart';
import '../../features/earnings/providers/earnings_providers.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/notifications/services/pending_notification_read_store.dart';
import '../../features/profile/providers/verification_provider.dart';
import '../di/providers.dart';
import '../providers/pending_request_recovery_provider.dart';
import '../providers/socket_provider.dart';
import '../providers/nav_badge_provider.dart';
import '../utils/incoming_ride_fare_copy.dart';
import 'local_notification_service.dart';
import 'ride_cancellation_notice.dart';
import 'incoming_request_action_bridge.dart';
import 'incoming_request_overlay_presenter.dart';
import 'job_offer_receipt_service.dart';
import 'live_activity_service.dart';
import 'ride_offer_receipt_service.dart';

const _defaultIncomingCallTimeout = Duration(seconds: 60);
const _terminalCallTombstoneFallback = Duration(minutes: 2);
const _terminalCallTombstonePrefix = 'myshop.call_terminal.';

/// Device-token capability, deliberately distinct from the per-offer payload
/// protocol. Existing 1.4.7 builds already advertise v2 for ride/ActivityKit
/// receipts; v3 is the first build that can durably ACK exact artisan jobs.
@visibleForTesting
const int providerOfferReceiptCapabilityVersion = 3;

@visibleForTesting
const int legacyProviderOfferReceiptCapabilityVersion = 2;

@visibleForTesting
bool isOfferReceiptCapabilityValidationError(ApiException error) {
  if (error.statusCode != 400 && error.statusCode != 422) return false;
  final diagnostic = <Object?>[
    error.message,
    error.errorCode,
    error.details,
  ].join(' ').replaceAll('_', '').toLowerCase();
  return diagnostic.contains('offerreceiptversion');
}

@visibleForTesting
bool notificationAuthorizationAllowsOnline(AuthorizationStatus status) {
  return status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;
}

@visibleForTesting
bool rideRequestNavigationAlreadyActive({
  required String rideId,
  required String? visibleRideId,
  required Set<String> navigationInFlightRideIds,
}) {
  return visibleRideId == rideId || navigationInFlightRideIds.contains(rideId);
}

@visibleForTesting
bool notificationHydrationSessionIsCurrent({
  required Object? expectedSession,
  required Object? currentSession,
}) {
  return expectedSession != null && currentSession == expectedSession;
}

@visibleForTesting
bool isActionableJobOfferPayload(
  String type,
  Map<String, dynamic> payload,
) {
  if (type == NotificationPayload.typeJobRequest) return true;
  if (type != NotificationPayload.typeJobManuallyAssigned) return false;
  final mode = (payload['mode'] ?? payload['assignmentMode'])
      ?.toString()
      .trim()
      .toLowerCase();
  final version = int.tryParse(payload['offerVersion']?.toString() ?? '');
  return mode == 'request_quote' && version == jobOfferReceiptProtocolVersion;
}

@visibleForTesting
const rideRequestNavigationFallbackDuration = Duration(seconds: 12);

@visibleForTesting
bool releaseRideRequestNavigationLatchIfOwned({
  required Map<String, Object> latchTokens,
  required String rideId,
  required Object token,
  required VoidCallback onRelease,
}) {
  if (!identical(latchTokens[rideId], token)) return false;
  latchTokens.remove(rideId);
  onRelease();
  return true;
}

@visibleForTesting
bool shouldNavigateToActiveRideFromNotification(String currentPath) {
  return currentPath != '/active-ride';
}

/// Settlement pushes mutate the provider's available balance and payout
/// state. They must refresh earnings even when received in the foreground and
/// the provider never taps the notification.
@visibleForTesting
bool isEarningsSettlementNotification(String type) {
  return type == NotificationPayload.typePaymentReceived ||
      type == NotificationPayload.typeEarningsUpdated ||
      type == NotificationPayload.typeRideSettled ||
      type == NotificationPayload.typeJobPaymentReleasing ||
      type == NotificationPayload.typeJobConfirmedComplete;
}

/// Coalesces the multiple platform callbacks that can represent one physical
/// incoming-request tap.
///
/// A request action can reach Dart through FlutterFire, the local notification
/// plugin, and the durable native action bridge. Those callbacks do not share
/// a platform event id, so deduplicating only by native queue id still lets one
/// View/Accept tap hydrate or mutate the same request multiple times.
///
/// View callbacks are single-flight and retain a short success tombstone. A
/// later explicit decision remains valid. Once Accept/Skip/Bid owns a request,
/// all duplicate decisions and trailing View callbacks are suppressed for the
/// rest of the offer window.
@visibleForTesting
class IncomingRequestTapCoordinator {
  IncomingRequestTapCoordinator({
    this.viewReplayWindow = const Duration(seconds: 30),
    this.decisionFallbackWindow = const Duration(seconds: 30),
  });

  final Duration viewReplayWindow;
  final Duration decisionFallbackWindow;

  final Map<String, Future<void>> _activeViews = <String, Future<void>>{};
  final Map<String, Future<void>> _activeDecisions = <String, Future<void>>{};
  final Map<String, Timer> _viewTombstones = <String, Timer>{};
  final Map<String, Timer> _decisionTombstones = <String, Timer>{};
  final Map<String, Set<String>> _equivalentRequestKeys =
      <String, Set<String>>{};
  var _generation = 0;
  var _disposed = false;

  Future<bool> dispatch(
    Map<String, dynamic> payload,
    Future<void> Function() handle,
  ) async {
    if (_disposed) return false;
    final requestKeys = _expandedRequestKeys(payload);
    if (requestKeys.isEmpty) {
      await handle();
      return true;
    }
    final requestLabel = requestKeys.join('|');
    final generation = _generation;

    final isDecision = _isDecision(payload);
    if (isDecision) {
      final activeDecision = _firstActive(_activeDecisions, requestKeys);
      if (activeDecision != null) {
        // Durable native copies must not acknowledge before the canonical
        // action has succeeded. Awaiting the same Future preserves replay on
        // failure while still preventing a second API mutation.
        await activeDecision;
        debugPrint('[RequestTap] joined duplicate decision for $requestLabel');
        return false;
      }
      if (_containsAny(_decisionTombstones, requestKeys)) {
        debugPrint(
          '[RequestTap] suppressed duplicate decision for $requestLabel',
        );
        return false;
      }
      final operation = Future<void>.sync(handle);
      _bindActive(_activeDecisions, requestKeys, operation);
      try {
        await operation;
        if (generation == _generation) {
          _removeActive(_activeDecisions, requestKeys, operation);
        }
        if (generation == _generation && !_disposed) {
          _rememberAll(
            _decisionTombstones,
            requestKeys,
            _decisionWindow(payload),
          );
        }
        return true;
      } catch (_) {
        // The native bridge deliberately replays unacknowledged actions.
        // Unexpected failures must therefore remain retryable.
        if (generation == _generation) {
          _removeActive(_activeDecisions, requestKeys, operation);
        }
        rethrow;
      }
    }

    final activeDecision = _firstActive(_activeDecisions, requestKeys);
    if (activeDecision != null) {
      await activeDecision;
      debugPrint(
        '[RequestTap] joined decision before duplicate view for $requestLabel',
      );
      return false;
    }
    final activeView = _firstActive(_activeViews, requestKeys);
    if (activeView != null) {
      await activeView;
      debugPrint('[RequestTap] joined duplicate view for $requestLabel');
      return false;
    }
    if (_containsAny(_decisionTombstones, requestKeys) ||
        _containsAny(_viewTombstones, requestKeys)) {
      debugPrint('[RequestTap] suppressed duplicate view for $requestLabel');
      return false;
    }
    final operation = Future<void>.sync(handle);
    _bindActive(_activeViews, requestKeys, operation);
    try {
      await operation;
      if (generation == _generation) {
        _removeActive(_activeViews, requestKeys, operation);
      }
      if (generation == _generation && !_disposed) {
        _rememberAll(_viewTombstones, requestKeys, _viewWindow(payload));
      }
      return true;
    } catch (_) {
      if (generation == _generation) {
        _removeActive(_activeViews, requestKeys, operation);
      }
      rethrow;
    }
  }

  /// A View callback may begin just before an Accept/Skip callback claims the
  /// same request. Re-check immediately before navigation so the decision wins
  /// and the older View cannot reopen the request screen afterwards.
  bool shouldAbortViewAfterDecision(Map<String, dynamic> payload) {
    if (_isDecision(payload)) return false;
    final requestKeys = _expandedRequestKeys(payload);
    return _containsAny(_activeDecisions, requestKeys) ||
        _containsAny(_decisionTombstones, requestKeys);
  }

  /// A ride loader that could not hydrate deliberately reopens the navigation
  /// latch. Remove only the short View replay claim as well so the provider can
  /// tap the still-live notification and try again immediately.
  void allowViewRetry(Map<String, dynamic> payload) {
    if (_isDecision(payload)) return;
    for (final requestKey in _expandedRequestKeys(payload)) {
      _viewTombstones.remove(requestKey)?.cancel();
    }
  }

  /// Session-owned claims must never carry into another provider account.
  void reset() {
    _generation += 1;
    for (final timer in _viewTombstones.values) {
      timer.cancel();
    }
    for (final timer in _decisionTombstones.values) {
      timer.cancel();
    }
    _viewTombstones.clear();
    _decisionTombstones.clear();
    _activeViews.clear();
    _activeDecisions.clear();
    _equivalentRequestKeys.clear();
  }

  void dispose() {
    _disposed = true;
    reset();
  }

  Set<String> _requestKeys(Map<String, dynamic> payload) {
    final nested = payload['data'];
    final nestedData = nested is Map
        ? Map<String, dynamic>.from(nested)
        : const <String, dynamic>{};
    String? valueFor(List<String> keys) {
      for (final source in [payload, nestedData]) {
        for (final key in keys) {
          final value = source[key]?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
      return null;
    }

    final rawType =
        valueFor([NotificationPayload.keyType, 'requestType']) ?? '';
    final type = NotificationPayload.normaliseType(rawType);
    final rideId = valueFor([
      NotificationPayload.keyRideId,
      'ride_id',
      'requestId',
    ]);
    final jobId = valueFor([
      NotificationPayload.keyJobId,
      'job_id',
      'requestId',
    ]);
    final offerId = valueFor([NotificationPayload.keyOfferId, 'offer_id']);

    if (type == NotificationPayload.typeRideRequest ||
        _isRideRequestAction(payload)) {
      return <String>{
        if (rideId != null) 'ride-id:$rideId',
        if (offerId != null) 'ride-offer:$offerId',
      };
    }
    if (type == NotificationPayload.typeJobRequest ||
        _isJobRequestAction(payload)) {
      return <String>{
        if (jobId != null) 'job-id:$jobId',
        if (offerId != null) 'job-offer:$offerId',
      };
    }
    return const <String>{};
  }

  Set<String> _expandedRequestKeys(Map<String, dynamic> payload) {
    final directKeys = _requestKeys(payload);
    if (directKeys.isEmpty) return directKeys;

    final expanded = <String>{...directKeys};
    var changed = true;
    while (changed) {
      changed = false;
      for (final key in List<String>.of(expanded)) {
        final aliases = _equivalentRequestKeys[key];
        if (aliases == null) continue;
        final previousLength = expanded.length;
        expanded.addAll(aliases);
        if (expanded.length != previousLength) changed = true;
      }
    }

    // A canonical payload normally carries both requestId and offerId. Retain
    // that equivalence so a later platform callback carrying only one alias
    // still joins the operation that already owns the physical request.
    if (expanded.length > 1) {
      final equivalence = Set<String>.unmodifiable(expanded);
      for (final key in expanded) {
        _equivalentRequestKeys[key] = equivalence;
      }
    }
    return expanded;
  }

  bool _isDecision(Map<String, dynamic> payload) {
    final action = _normalisedAction(payload);
    return action == NotificationPayload.actionRideAccept ||
        action == NotificationPayload.actionRideSkip ||
        action == NotificationPayload.actionJobSkip;
  }

  bool _isRideRequestAction(Map<String, dynamic> payload) {
    final action = _normalisedAction(payload);
    return action == NotificationPayload.actionRideView ||
        action == NotificationPayload.actionRideAccept ||
        action == NotificationPayload.actionRideSkip;
  }

  bool _isJobRequestAction(Map<String, dynamic> payload) {
    final action = _normalisedAction(payload);
    return action == NotificationPayload.actionJobView ||
        action == NotificationPayload.actionJobSubmitBid ||
        action == NotificationPayload.actionJobSkip;
  }

  String? _normalisedAction(Map<String, dynamic> payload) {
    final direct = payload[NotificationPayload.keyActionId];
    final nested = payload['data'];
    final nestedAction =
        nested is Map ? nested[NotificationPayload.keyActionId] : null;
    return (direct ?? nestedAction)?.toString().trim().toUpperCase();
  }

  Duration _decisionWindow(Map<String, dynamic> payload) {
    final nested = payload['data'];
    final nestedOffer = nested is Map
        ? nested[NotificationPayload.keyOfferId] ?? nested['offer_id']
        : null;
    final offerId = (payload[NotificationPayload.keyOfferId] ??
                payload['offer_id'] ??
                nestedOffer)
            ?.toString()
            .trim() ??
        '';
    if (offerId.isEmpty) {
      // Legacy payloads cannot distinguish a later re-offer of the same
      // booking. Keep only the immediate cross-channel replay guard.
      return viewReplayWindow;
    }
    final now = DateTime.now().toUtc();
    final deadline = _requestDeadlineFromData(payload);
    if (deadline == null || !deadline.isAfter(now)) {
      return decisionFallbackWindow;
    }
    final remaining = deadline.difference(now);
    // A malformed remote deadline must not retain an in-memory claim forever.
    const maximum = Duration(minutes: 2);
    return remaining > maximum ? decisionFallbackWindow : remaining;
  }

  Duration _viewWindow(Map<String, dynamic> payload) {
    final now = DateTime.now().toUtc();
    final deadline = _requestDeadlineFromData(payload);
    if (deadline == null || !deadline.isAfter(now)) {
      return viewReplayWindow;
    }
    final remaining = deadline.difference(now);
    const maximum = Duration(minutes: 2);
    return remaining > maximum ? viewReplayWindow : remaining;
  }

  Future<void>? _firstActive(
    Map<String, Future<void>> active,
    Set<String> requestKeys,
  ) {
    for (final requestKey in requestKeys) {
      final operation = active[requestKey];
      if (operation != null) return operation;
    }
    return null;
  }

  bool _containsAny<T>(Map<String, T> values, Set<String> requestKeys) {
    return requestKeys.any(values.containsKey);
  }

  void _bindActive(
    Map<String, Future<void>> active,
    Set<String> requestKeys,
    Future<void> operation,
  ) {
    for (final requestKey in requestKeys) {
      active[requestKey] = operation;
    }
  }

  void _removeActive(
    Map<String, Future<void>> active,
    Set<String> requestKeys,
    Future<void> operation,
  ) {
    for (final requestKey in requestKeys) {
      if (identical(active[requestKey], operation)) {
        active.remove(requestKey);
      }
    }
  }

  void _rememberAll(
    Map<String, Timer> tombstones,
    Set<String> requestKeys,
    Duration duration,
  ) {
    for (final requestKey in requestKeys) {
      _remember(tombstones, requestKey, duration);
    }
  }

  void _remember(
    Map<String, Timer> tombstones,
    String requestKey,
    Duration duration,
  ) {
    tombstones.remove(requestKey)?.cancel();
    final bounded =
        duration > Duration.zero ? duration : const Duration(milliseconds: 1);
    late final Timer timer;
    timer = Timer(bounded, () {
      if (identical(tombstones[requestKey], timer)) {
        tombstones.remove(requestKey);
      }
    });
    tombstones[requestKey] = timer;
  }
}

Future<void> _recordTerminalCallTombstone(
  String callId,
  Map<String, dynamic> data,
) async {
  try {
    final now = DateTime.now();
    final rawExpiresAt = data[NotificationPayload.keyExpiresAt]?.toString();
    final parsedExpiresAt =
        rawExpiresAt == null ? null : DateTime.tryParse(rawExpiresAt);
    final expiresAt = parsedExpiresAt != null && parsedExpiresAt.isAfter(now)
        ? parsedExpiresAt
        : now.add(_terminalCallTombstoneFallback);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.setInt(
      '$_terminalCallTombstonePrefix$callId',
      expiresAt.millisecondsSinceEpoch,
    );
  } catch (error) {
    debugPrint('[FCM] terminal tombstone write failed for $callId: $error');
  }
}

Future<bool> _hasTerminalCallTombstone(String callId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final key = '$_terminalCallTombstonePrefix$callId';
    final expiresAtMillis = prefs.getInt(key);
    if (expiresAtMillis == null) return false;
    if (expiresAtMillis > DateTime.now().millisecondsSinceEpoch) return true;
    await prefs.remove(key);
  } catch (error) {
    debugPrint('[FCM] terminal tombstone read failed for $callId: $error');
  }
  return false;
}

/// Background isolate handler — must be a top-level function annotated with
/// `@pragma('vm:entry-point')`.
///
/// When the app is terminated or the user is in another app, FCM spins up
/// a short-lived isolate, calls this, and then tears it down. We use it to
/// display a local notification (FCM alone would show a default system one
/// without tap payload).
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // Breadcrumb: confirms the OS actually woke the isolate. Visible via
  // `adb logcat | grep flutter` even when the app isn't running. If
  // jobs are being created and this line never appears, the message
  // never reached the device — investigate FCM token registration,
  // OEM battery optimisation (Xiaomi/Huawei/Samsung kill apps that
  // aren't whitelisted), or `notification.send()` failures on the
  // backend.
  debugPrint(
    '[FCM-bg] message arrived: '
    'type=${message.data['type']} '
    'hasNotificationField=${message.notification != null} '
    'keys=${message.data.keys.toList()}',
  );

  if (await _handleOfferRevokedFromRemote(message, source: 'background-fcm')) {
    return;
  }
  if (await _handleCallEndedFromRemote(message, source: 'background-fcm')) {
    return;
  }
  if (await _showIncomingCallFromRemote(message, source: 'background-fcm')) {
    return;
  }

  final backgroundType = _remoteType(message);
  var requestData = Map<String, dynamic>.from(message.data);
  if (backgroundType == NotificationPayload.typeRideRequest) {
    final received = await acknowledgeRideOfferFromBackground(requestData);
    if (received == null) {
      debugPrint('[FCM-bg] ride offer receipt failed; request not surfaced');
      return;
    }
    requestData = received.payload;
  }
  final actionableJobOffer =
      isActionableJobOfferPayload(backgroundType ?? '', requestData);
  if (actionableJobOffer) {
    final received = await acknowledgeJobOfferFromBackground(requestData);
    if (received == null) {
      debugPrint('[FCM-bg] job offer receipt failed; request not surfaced');
      return;
    }
    requestData = received.payload;
    // Native request surfaces understand the canonical job-request type. The
    // original server notification remains job_manually_assigned in the inbox;
    // only this actionable tray copy is normalised for View/Skip/Bid actions.
    requestData[NotificationPayload.keyType] =
        NotificationPayload.typeJobRequest;
  }
  if (Platform.isAndroid &&
      (backgroundType == NotificationPayload.typeRideRequest ||
          actionableJobOffer)) {
    final shown = await IncomingRequestOverlayPresenter.instance.showFromPush(
      requestData,
      notificationTitle:
          message.notification?.title ?? message.data['title']?.toString(),
    );
    if (shown) {
      debugPrint('[FCM-bg] native request overlay displayed: $backgroundType');
      return;
    }
    debugPrint('[FCM-bg] overlay unavailable; using notification fallback');
  }

  // FCM auto-displays hybrid pushes (top-level `notification`) while the
  // app is backgrounded/terminated. For normal timeline/chat pushes that is
  // exactly what we want because rendering locally as well produces duplicate
  // banners. Incoming work/ride requests are the exception: on Android they
  // must use our local request channel so they stay sticky until timeout and
  // play the MyShop request ringtone. Backend should already send those as
  // Android data-only pushes, but this defensive branch keeps the provider
  // alert usable if any backend path still includes a notification field.
  if (_shouldSkipLocalBackgroundRender(message) && !actionableJobOffer) {
    debugPrint(
      '[FCM-bg] FCM SDK will auto-display non-request push — '
      'skipping local render',
    );
    return;
  }
  // Re-initialise the local notification plugin inside this isolate —
  // state from the main isolate is NOT shared.
  await LocalNotificationService.instance.init();
  await _renderFromRemote(message, dataOverride: requestData);
  debugPrint('[FCM-bg] local notification rendered');
}

Future<bool> _handleOfferRevokedFromRemote(
  RemoteMessage message, {
  required String source,
}) async {
  if (_remoteType(message) != NotificationPayload.typeOfferRevoked) {
    return false;
  }

  final offerType = NotificationPayload.normaliseType(
    message.data['offerType']?.toString() ?? '',
  );
  final rideId = message.data[NotificationPayload.keyRideId]?.toString();
  final jobId = message.data[NotificationPayload.keyJobId]?.toString();
  final inferredType = offerType == NotificationPayload.typeRideRequest ||
          offerType == 'ride'
      ? NotificationPayload.typeRideRequest
      : offerType == NotificationPayload.typeJobRequest || offerType == 'job'
          ? NotificationPayload.typeJobRequest
          : rideId != null && rideId.isNotEmpty
              ? NotificationPayload.typeRideRequest
              : jobId != null && jobId.isNotEmpty
                  ? NotificationPayload.typeJobRequest
                  : null;
  final requestId = inferredType == NotificationPayload.typeRideRequest
      ? rideId
      : inferredType == NotificationPayload.typeJobRequest
          ? jobId
          : null;

  if (inferredType != null && requestId != null && requestId.isNotEmpty) {
    final reason = message.data['reason']?.toString() ?? 'revoked';
    final offerId = message.data[NotificationPayload.keyOfferId]?.toString();
    await clearIncomingRequestAlert(
      type: inferredType,
      requestId: requestId,
      offerId: offerId,
      reason: reason,
    );
    if (inferredType == NotificationPayload.typeRideRequest &&
        offerId != null &&
        offerId.isNotEmpty) {
      await clearStoredRideOffer(offerId);
    }
    if (inferredType == NotificationPayload.typeJobRequest &&
        offerId != null &&
        offerId.isNotEmpty) {
      await clearStoredJobOffer(offerId);
    }
    if (inferredType == NotificationPayload.typeRideRequest &&
        isRiderCancellationRevocation(reason)) {
      await LocalNotificationService.instance.init();
      await LocalNotificationService.instance.showTimelineUpdate(
        type: NotificationPayload.typeRideCancelled,
        title: 'Ride request cancelled',
        body: 'The rider cancelled this ride request.',
        extras: {NotificationPayload.keyRideId: requestId, 'reason': reason},
      );
    }
    debugPrint('[FCM] $source cleared revoked $inferredType $requestId');
  } else {
    debugPrint('[FCM] $source offer_revoked missing request identity');
  }
  return true;
}

Future<bool> _showIncomingCallFromRemote(
  RemoteMessage message, {
  required String source,
}) async {
  final type = _remoteType(message);
  if (type != NotificationPayload.typeCallIncoming) return false;

  final callId = message.data[NotificationPayload.keyCallId]?.toString();
  if (callId == null || callId.isEmpty) {
    debugPrint(
      '[FCM] $source call_incoming missing callId; '
      'keys=${message.data.keys.toList()}',
    );
    return true;
  }

  if (await _hasTerminalCallTombstone(callId)) {
    if (Platform.isAndroid) {
      await LocalNotificationService.instance.cancelIncomingCall(callId);
    }
    debugPrint('[FCM] $source ignored terminal call_incoming: $callId');
    return true;
  }

  final remaining = _remainingCallTimeout(message.data);
  if (remaining <= Duration.zero) {
    if (Platform.isAndroid) {
      await LocalNotificationService.instance.cancelIncomingCall(callId);
    }
    debugPrint('[FCM] $source ignored stale call_incoming: $callId');
    return true;
  }

  if (Platform.isAndroid) {
    await LocalNotificationService.instance.init();
    await _renderFromRemote(message, callTimeout: remaining);
    debugPrint('[FCM] $source call_incoming displayed on Android: $callId');
    return true;
  }

  if (!Platform.isIOS) {
    debugPrint('[FCM] $source call_incoming ignored on $_platformName');
    return true;
  }

  final payload = <String, dynamic>{...message.data};
  payload['title'] ??= message.notification?.title ?? 'Incoming MyShop call';
  payload['body'] ??=
      message.notification?.body ?? 'Someone is calling in MyShop';

  try {
    await VoipCallBridgeService.instance.showIncomingCall(payload);
    debugPrint('[FCM] $source call_incoming displayed with CallKit: $callId');
    return true;
  } catch (error) {
    debugPrint('[FCM] $source CallKit fallback failed for $callId: $error');
    return false;
  }
}

Future<bool> _handleCallEndedFromRemote(
  RemoteMessage message, {
  required String source,
}) async {
  if (_remoteType(message) != NotificationPayload.typeCallEnded) return false;

  final callId = message.data[NotificationPayload.keyCallId]?.toString();
  if (callId == null || callId.isEmpty) {
    debugPrint(
      '[FCM] $source call_ended missing callId; '
      'keys=${message.data.keys.toList()}',
    );
    return true;
  }

  await _recordTerminalCallTombstone(callId, message.data);

  try {
    if (Platform.isAndroid) {
      await LocalNotificationService.instance.cancelIncomingCall(callId);
    } else if (Platform.isIOS) {
      await VoipCallBridgeService.instance.endCall(callId);
    }
    debugPrint('[FCM] $source call_ended cleared incoming call: $callId');
  } catch (error) {
    debugPrint('[FCM] $source call_ended clear failed for $callId: $error');
  }
  return true;
}

String? _remoteType(RemoteMessage message) {
  final rawType = message.data[NotificationPayload.keyType]?.toString();
  if (rawType == null || rawType.isEmpty) return null;
  return NotificationPayload.normaliseType(rawType);
}

Duration _remainingCallTimeout(Map<String, dynamic> data) {
  final rawExpiresAt = data[NotificationPayload.keyExpiresAt]?.toString();
  if (rawExpiresAt == null || rawExpiresAt.isEmpty) {
    return _defaultIncomingCallTimeout;
  }
  final expiresAt = DateTime.tryParse(rawExpiresAt);
  if (expiresAt == null) return Duration.zero;
  return expiresAt.difference(DateTime.now());
}

DateTime? _requestDeadlineFromData(Map<String, dynamic> data) {
  final nested = data['data'];
  final sources = <Map<String, dynamic>>[
    data,
    if (nested is Map) Map<String, dynamic>.from(nested),
  ];
  for (final source in sources) {
    for (final key in const <String>[
      'expiresAt',
      'expires_at',
      'acceptanceExpiresAt',
      'acceptance_expires_at',
      'requestExpiresAt',
      'request_expires_at',
      'decisionExpiresAt',
      'decision_expires_at',
      'serverDecisionExpiresAt',
      'server_decision_expires_at',
    ]) {
      final raw = source[key]?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
  }
  for (final source in sources) {
    for (final key in const <String>[
      'expiresInSeconds',
      'expires_in_seconds',
      'acceptanceWindowSeconds',
      'acceptance_window_seconds',
      'decisionWindowSeconds',
      'decision_window_seconds',
    ]) {
      final raw = source[key];
      final seconds = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (seconds != null && seconds > 0) {
        return DateTime.now().toUtc().add(Duration(seconds: seconds));
      }
    }
  }
  return null;
}

Duration _remainingRequestTimeout(Map<String, dynamic> data) {
  final deadline = _requestDeadlineFromData(data);
  if (deadline == null) return Duration.zero;
  return deadline.difference(DateTime.now().toUtc());
}

String get _platformName {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'unknown';
}

bool _shouldSkipLocalBackgroundRender(RemoteMessage message) {
  if (message.notification == null) return false;

  final rawType = message.data[NotificationPayload.keyType]?.toString() ?? '';
  final type = NotificationPayload.normaliseType(rawType);

  final shouldUseLocalRequestAlert = Platform.isAndroid &&
      NotificationPayload.persistentRequestTypes.contains(type);
  if (shouldUseLocalRequestAlert) {
    debugPrint(
      '[FCM-bg] Android incoming request has notification field; '
      'rendering local sticky request alert anyway',
    );
    return false;
  }

  return true;
}

Future<void> _renderFromRemote(
  RemoteMessage message, {
  Duration? callTimeout,
  Map<String, dynamic>? dataOverride,
}) async {
  final data = dataOverride ?? message.data;
  final type = NotificationPayload.normaliseType(
    data[NotificationPayload.keyType]?.toString() ?? '',
  );
  if (type.isEmpty) return;

  final callId = data[NotificationPayload.keyCallId]?.toString();
  if (type == NotificationPayload.typeCallEnded) {
    if (callId != null && callId.isNotEmpty) {
      await LocalNotificationService.instance.cancelIncomingCall(callId);
    }
    return;
  }

  Duration? timeoutAfter;
  if (type == NotificationPayload.typeCallIncoming) {
    if (callId == null || callId.isEmpty) {
      debugPrint(
        '[FCM] call_incoming missing callId; keys=${data.keys.toList()}',
      );
      return;
    }
    timeoutAfter = callTimeout ?? _remainingCallTimeout(data);
    if (timeoutAfter <= Duration.zero) {
      await LocalNotificationService.instance.cancelIncomingCall(callId);
      debugPrint('[FCM] ignored stale call_incoming: $callId');
      return;
    }
  } else if (type == NotificationPayload.typeRideRequest ||
      type == NotificationPayload.typeJobRequest) {
    timeoutAfter = _remainingRequestTimeout(data);
    if (timeoutAfter <= Duration.zero) {
      final requestId = type == NotificationPayload.typeRideRequest
          ? data[NotificationPayload.keyRideId]?.toString()
          : data[NotificationPayload.keyJobId]?.toString();
      if (requestId != null && requestId.isNotEmpty) {
        await clearIncomingRequestAlert(
          type: type,
          requestId: requestId,
          offerId: data[NotificationPayload.keyOfferId]?.toString(),
        );
      }
      debugPrint('[FCM] ignored stale $type request');
      return;
    }
  }

  var title = message.notification?.title ?? data['title']?.toString() ?? '';
  var body = message.notification?.body ?? data['body']?.toString() ?? '';
  if (type == NotificationPayload.typeRideRequest ||
      type == NotificationPayload.typeJobRequest) {
    title = type == NotificationPayload.typeRideRequest
        ? 'New ride request'
        : 'New job request';
    body = privacySafeRequestBody(type, data);
  }

  // Preserve tap-routing context without copying provider economics into the
  // OS-owned local-notification payload.
  final extras = privacySafeRequestExtras(type, data);

  await LocalNotificationService.instance.showTimelineUpdate(
    type: type,
    title: title.isEmpty ? _fallbackTitle(type) : title,
    body: body.isEmpty ? _fallbackBody(type) : body,
    extras: extras,
    timeoutAfter: timeoutAfter,
  );
}

@visibleForTesting
Map<String, String> privacySafeRequestExtras(
  String type,
  Map<String, dynamic> data,
) {
  const providerEconomicsKeys = <String>{
    'commissionPesewas',
    'commission_pesewas',
    'commissionRatePercent',
    'commission_rate_percent',
    'estimatedProviderEarningsPesewas',
    'estimated_provider_earnings_pesewas',
    'providerEarningsPesewas',
    'provider_earnings_pesewas',
    'netPayoutPesewas',
    'net_payout_pesewas',
  };
  final stripProviderEconomics = NotificationPayload.normaliseType(type) ==
      NotificationPayload.typeRideRequest;

  Object? withoutProviderEconomics(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!providerEconomicsKeys.contains(entry.key.toString()))
            entry.key.toString(): withoutProviderEconomics(entry.value),
      };
    }
    if (value is List) return value.map(withoutProviderEconomics).toList();
    return value;
  }

  final extras = <String, String>{};
  for (final entry in data.entries) {
    if (entry.key == NotificationPayload.keyType) continue;
    if (entry.key == 'title' || entry.key == 'body') continue;
    if (stripProviderEconomics && providerEconomicsKeys.contains(entry.key)) {
      continue;
    }
    var value = entry.value;
    if (stripProviderEconomics && value is String) {
      final raw = value;
      final trimmed = raw.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          value = json.encode(withoutProviderEconomics(json.decode(raw)));
        } catch (_) {
          if (providerEconomicsKeys.any(raw.contains)) continue;
        }
      }
    }
    if (value is String && value.isNotEmpty) extras[entry.key] = value;
  }
  return extras;
}

@visibleForTesting
String privacySafeRequestBody(String type, Map<String, dynamic> data) {
  Map<String, dynamic> decoded(String key) {
    final raw = data[key];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.isEmpty) return const <String, dynamic>{};
    try {
      final value = json.decode(raw);
      return value is Map
          ? Map<String, dynamic>.from(value)
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  final details = <String, dynamic>{
    ...decoded('offerPayload'),
    ...decoded('ridePayload'),
    ...decoded('jobPayload'),
  };
  String? value(Object? raw) {
    final text = raw?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  num? number(Object? raw) => switch (raw) {
        final num raw => raw,
        final Object raw => num.tryParse(raw.toString()),
        null => null,
      };

  if (type == NotificationPayload.typeRideRequest) {
    final wire = <String, dynamic>{...data, ...details};
    final fare = IncomingRideFareCopy.fromSnapshot(
      IncomingRideFareSnapshot.fromJson(wire),
    );
    final distance = number(details['distanceKm'] ?? data['distanceKm']);
    final parts = <String>[
      for (final line in fare.pricingLines)
        '${_sentenceCaseRequestCopy(line.label)} ${line.amount}',
      if (distance != null) '${distance.toStringAsFixed(1)} km',
    ];
    return parts.isEmpty
        ? 'Unlock to view pickup and destination.'
        : '${parts.join(' · ')} · Unlock to view route.';
  }

  final category = value(details['categoryName'] ?? data['categoryName']);
  final distanceMeters = number(
    details['distanceMeters'] ?? data['distanceMeters'],
  );
  final minBid = number(
    details['minBidPesewas'] ??
        details['minimumBidPesewas'] ??
        data['minBidPesewas'],
  );
  final parts = <String>[
    if (category != null) category,
    if (distanceMeters != null)
      '${(distanceMeters / 1000).toStringAsFixed(1)} km',
    if (minBid != null) 'Minimum GHS ${(minBid / 100).toStringAsFixed(2)}',
  ];
  return parts.isEmpty
      ? 'Unlock to view description, location, and photos.'
      : '${parts.join(' · ')} · Unlock to view details.';
}

String _sentenceCaseRequestCopy(String value) {
  final lower = value.toLowerCase();
  return lower.isEmpty
      ? lower
      : '${lower[0].toUpperCase()}${lower.substring(1)}';
}

String _fallbackTitle(String type) {
  switch (type) {
    case NotificationPayload.typeJobRequest:
      return 'New job request';
    case NotificationPayload.typeRideRequest:
      return 'New ride request';
    case NotificationPayload.typeBidAccepted:
      return 'Your bid was accepted';
    case NotificationPayload.typeBidRejected:
      return 'Bid rejected';
    case NotificationPayload.typeJobCancelled:
    case NotificationPayload.typeJobCancelledByClient:
      return 'Job cancelled';
    case NotificationPayload.typeJobConfirmedComplete:
      return 'Job confirmed';
    case NotificationPayload.typeJobPaymentReleasing:
      return 'Payout on the way';
    case NotificationPayload.typeJobManuallyAssigned:
      return 'Job assigned to you';
    case NotificationPayload.typeJobNoBidsEscalated:
      return 'Open job — your bid is welcome';
    case NotificationPayload.typeProviderResponseBlockWarning:
      return 'Response warning';
    case NotificationPayload.typeProviderResponseBlockStarted:
      return 'New requests paused';
    case NotificationPayload.typeJobReminder24h:
      return 'Job tomorrow';
    case NotificationPayload.typeJobReminder2h:
      return 'Job starts in 2 hours';
    case NotificationPayload.typeJobCheckin8h:
      return 'How is the job going?';
    case NotificationPayload.typeJobStale24h:
      return 'Job needs an update';
    case NotificationPayload.typeJobStale48h:
      return 'Job will auto-cancel soon';
    case NotificationPayload.typeJobWelfareCheck:
      return 'Quick welfare check';
    case NotificationPayload.typeSupplementApproved:
      return 'Supplement approved';
    case NotificationPayload.typeSupplementRejected:
      return 'Supplement rejected';
    case NotificationPayload.typeRideCancelled:
      return 'Ride cancelled';
    case NotificationPayload.typeRideSettled:
      return 'Ride settled';
    case NotificationPayload.typeNewMessage:
      return 'New message';
    case NotificationPayload.typePaymentReceived:
      return 'Payout received';
    case NotificationPayload.typeEarningsUpdated:
      return 'Earnings updated';
    case NotificationPayload.typeRatingPrompt:
      return 'Rate your client';
    case NotificationPayload.typeSupportTicketMessage:
      return 'New reply from support';
    case NotificationPayload.typeSupportTicketStatusChanged:
      return 'Ticket update';
    case NotificationPayload.typeProviderDocumentUploadConfirmed:
      return 'Document upload confirmed';
    case NotificationPayload.typeProviderDocumentExpiryNotice:
      return 'Document expires soon';
    case NotificationPayload.typeProviderDocumentExpiry72h:
      return 'Document invalid in 72 hours';
    case NotificationPayload.typeProviderDocumentExpiry24h:
      return 'Document invalid in 24 hours';
    case NotificationPayload.typeProviderDocumentExpiry2h:
      return 'Document invalid in 2 hours';
    case NotificationPayload.typeProviderDocumentExpired:
      return 'Document expired';
    case NotificationPayload.typeProviderDocumentReplacementGraceStarted:
      return 'Replacement awaiting review';
    case NotificationPayload.typeProviderDocumentReplacementGraceExpired:
      return 'Document action required';
    default:
      return 'MyShop';
  }
}

String _fallbackBody(String type) {
  switch (type) {
    case NotificationPayload.typeJobRequest:
      return 'A client has requested your services.';
    case NotificationPayload.typeRideRequest:
      return 'A passenger needs a ride.';
    case NotificationPayload.typeBidAccepted:
      return 'Tap to start the job.';
    case NotificationPayload.typeJobConfirmedComplete:
      return 'Your payout has been released.';
    case NotificationPayload.typeJobCancelled:
    case NotificationPayload.typeJobCancelledByClient:
      return 'The client cancelled this job.';
    case NotificationPayload.typeRideCancelled:
      return 'The client cancelled this ride.';
    case NotificationPayload.typeJobPaymentReleasing:
      return 'Your earnings settlement is being processed. Check Earnings for status.';
    case NotificationPayload.typeEarningsUpdated:
      return 'Open Earnings to see the latest server-confirmed balance.';
    case NotificationPayload.typeJobManuallyAssigned:
      return 'Tap to review and place your bid.';
    case NotificationPayload.typeJobNoBidsEscalated:
      return 'A nearby job needs an artisan. Tap to bid.';
    case NotificationPayload.typeProviderResponseBlockWarning:
      return 'Go offline when unavailable. Repeated declines or missed requests may pause new offers.';
    case NotificationPayload.typeProviderResponseBlockStarted:
      return 'Open MyShop to review the temporary pause or contact support.';
    case NotificationPayload.typeJobReminder24h:
      return 'You have a scheduled job tomorrow. Tap to review.';
    case NotificationPayload.typeJobReminder2h:
      return 'Time to head to the site. Tap to navigate.';
    case NotificationPayload.typeJobCheckin8h:
      return 'Drop a quick update so the client knows progress.';
    case NotificationPayload.typeJobStale24h:
      return 'No updates in 24 hours. Tap to advance the job.';
    case NotificationPayload.typeJobStale48h:
      return 'The job will auto-cancel without progress.';
    case NotificationPayload.typeJobWelfareCheck:
      return 'Tap to confirm everything is on track.';
    case NotificationPayload.typeRatingPrompt:
      return 'Tap to leave a rating before the 24-hour window closes.';
    case NotificationPayload.typeSupportTicketMessage:
      return 'Tap to read and reply.';
    case NotificationPayload.typeSupportTicketStatusChanged:
      return 'Tap to see the latest status.';
    case NotificationPayload.typeProviderDocumentUploadConfirmed:
      return 'Open Documents & Verification to view its independent review status.';
    case NotificationPayload.typeProviderDocumentExpiryNotice:
    case NotificationPayload.typeProviderDocumentExpiry72h:
    case NotificationPayload.typeProviderDocumentExpiry24h:
    case NotificationPayload.typeProviderDocumentExpiry2h:
      return 'Open Documents & Verification to review the renewal instructions.';
    case NotificationPayload.typeProviderDocumentExpired:
      return 'Finish any active trip, then replace the expired document before going online again.';
    case NotificationPayload.typeProviderDocumentReplacementGraceStarted:
      return 'Your existing approved document remains valid only until the stated review deadline.';
    case NotificationPayload.typeProviderDocumentReplacementGraceExpired:
      return 'Finish any active trip, then complete document review before going online again.';
    default:
      return 'Open MyShop to see the latest update.';
  }
}

/// FCM lifecycle coordinator.
///
///   1. [init] — wire handlers (background + foreground + tap) once at
///      app start.
///   2. [syncToken] — call after the user authenticates so the backend
///      knows where to route pushes. Also re-fires on token refresh.
///
/// [onTapMessage] is invoked when the user taps a system-tray notification
/// (either ours via [LocalNotificationService] or one FCM created). The
/// payload carries `{ type, jobId | rideId | bidId | chatId }` so the
/// router can deep-link.
class FcmService {
  FcmService(this._ref);

  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<RemoteMessage>? _openedMessageSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<VoipCallBridgeEvent>? _voipEventSub;
  StreamSubscription<LiveActivityBridgeEvent>? _liveActivityEventSub;
  StreamSubscription<AppCallSession>? _incomingCallStateSub;
  final Set<String> _trackedIncomingCallIds = <String>{};
  AuthSessionIdentity? _deviceRegistrationIdentity;
  AuthSessionIdentity? _voipRegistrationIdentity;
  AuthSessionIdentity? _liveActivityRegistrationIdentity;
  int _lifecycleEpoch = 0;
  bool _initialised = false;
  Future<void>? _initializing;

  /// Called with the payload map when a user taps a push (either from the
  /// background/terminated state or after a foreground message surfaces
  /// through [LocalNotificationService]).
  Future<void> Function(Map<String, dynamic> payload)? onTapMessage;

  Future<void> init() {
    debugPrint('[FCM] init() called (initialised=$_initialised)');
    if (_initialised) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    // Background isolate handler MUST be registered before any message
    // can arrive. Safe to call multiple times.
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    debugPrint('[FCM] background handler registered');

    // Do not show an OS permission prompt during startup. The explicit
    // Go Online action owns the contextual request through
    // ensureOnlineNotificationReachability().

    // Ensure tapping a local notification also routes via the same
    // handler the router will set.
    LocalNotificationService.instance.onTap = (payload) {
      unawaited(_markNotificationRead(payload));
      final handler = onTapMessage;
      if (handler != null) unawaited(handler(payload));
    };

    // Foreground messages — the in-app modal is driven by the socket in
    // IncomingRequestListener, so we just surface a local notification as
    // a fallback (useful if the socket is disconnected).
    //
    // `new_message`: only suppress the banner when the user is already
    // looking at the chat screen for THIS booking. Previously we
    // suppressed every foreground new_message blanket — that's why a
    // driver who was on /home or /earnings never saw a chat banner and
    // assumed messages weren't being delivered. The chat socket still
    // updates unread badges on those screens; we just also want a
    // heads-up banner when they're not actually in the chat.
    _foregroundMessageSub ??= FirebaseMessaging.onMessage.listen((
      message,
    ) async {
      debugPrint(
        '[FCM] foreground message: type=${message.data['type']} '
        'keys=${message.data.keys.toList()}',
      );
      if (await _handleOfferRevokedFromRemote(
        message,
        source: 'foreground-fcm',
      )) {
        final rideId = message.data[NotificationPayload.keyRideId]?.toString();
        final jobId = message.data[NotificationPayload.keyJobId]?.toString();
        if (rideId != null && rideId.isNotEmpty) {
          _ref.read(rideOfferDismissalProvider.notifier).state =
              RideOfferDismissal(
            rideId: rideId,
            reason: message.data['reason']?.toString() ?? 'revoked',
          );
          _ref.read(incomingRideRequestProvider.notifier).state = null;
          _ref
              .read(rideRequestDeadlineByIdProvider.notifier)
              .update((deadlines) => {...deadlines}..remove(rideId));
        }
        if (jobId != null && jobId.isNotEmpty) {
          final terminalOfferId =
              message.data[NotificationPayload.keyOfferId]?.toString();
          final currentOfferId = _ref.read(jobOfferIdByJobProvider)[jobId];
          if (jobOfferTerminalMatchesCurrent(
            currentOfferId: currentOfferId,
            terminalOfferId: terminalOfferId,
          )) {
            _ref.read(jobOfferDismissalProvider.notifier).state =
                JobOfferDismissal(
              jobId: jobId,
              reason: message.data['reason']?.toString() ?? 'revoked',
              offerId: terminalOfferId,
            );
            _ref.read(pendingIncomingJobsProvider.notifier).remove(jobId);
            _ref
                .read(jobOfferIdByJobProvider.notifier)
                .update((offers) => {...offers}..remove(jobId));
            _ref
                .read(jobOfferDeadlineByJobProvider.notifier)
                .update((deadlines) => {...deadlines}..remove(jobId));
            if (_ref.read(incomingJobRequestProvider)?.id == jobId) {
              _ref.read(incomingJobRequestProvider.notifier).state = null;
            }
          }
        }
        final reason = message.data['reason']?.toString();
        if (rideId != null &&
            rideId.isNotEmpty &&
            isRiderCancellationRevocation(reason) &&
            claimRiderCancellationInAppNotice(rideId)) {
          final router = _ref.read(goRouterProvider);
          final context = router.routerDelegate.navigatorKey.currentContext;
          if (context != null && context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('The rider cancelled this ride request.'),
                  duration: Duration(seconds: 5),
                ),
              );
          }
        }
        return;
      }
      if (await _handleCallEndedFromRemote(message, source: 'foreground-fcm')) {
        return;
      }
      if (await _showIncomingCallFromRemote(
        message,
        source: 'foreground-fcm',
      )) {
        if (Platform.isAndroid &&
            _remoteType(message) == NotificationPayload.typeCallIncoming) {
          _openAndroidIncomingCall(message.data);
        }
        return;
      }

      final rawType = message.data[NotificationPayload.keyType] as String?;
      final type = NotificationPayload.normaliseType(rawType ?? '');
      if (_ref.exists(providerNotifsProvider)) {
        // The push is only a wake-up hint. Refetch the persisted in-app rows
        // and authoritative unread total instead of trusting push-channel ids.
        unawaited(_ref.read(providerNotifsProvider.notifier).reload());
      }
      if (isEarningsSettlementNotification(type)) {
        // Start the authoritative refresh before rendering the notification.
        // A visible earnings screen keeps its historical totals but fences
        // the payout CTA until the new balance has arrived.
        _ref.read(refreshEarningsAfterSettlementProvider)();
      }
      if (providerDocumentLifecycleRoute(type) != null) {
        // A decision can arrive while Documents & Verification or Account is
        // already visible. Refresh immediately instead of requiring the user
        // to tap the banner or restart before the corrective state appears.
        _ref.invalidate(verificationStatusProvider);
        unawaited(
          _ref.read(authControllerProvider.notifier).refreshProfile(),
        );
      }
      if (type == NotificationPayload.typeRideRequest) {
        final received = await acknowledgeRideOfferWithSocket(
          payload: Map<String, dynamic>.from(message.data),
          socket: _ref.read(socketServiceProvider),
          rides: _ref.read(rideServiceProvider),
        );
        if (received == null) {
          debugPrint('[FCM] foreground ride offer receipt failed');
          return;
        }
        _ref
            .read(rideOfferIdByRideProvider.notifier)
            .update((offers) => {...offers, received.rideId: received.offerId});
        _ref.read(rideRequestDeadlineByIdProvider.notifier).update(
              (deadlines) => {
                ...deadlines,
                received.rideId: received.decisionExpiresAt,
              },
            );
        final active = _ref.read(activeRideProvider).ride;
        if (active?.id == received.rideId ||
            _ref.read(surfacedRideIdsProvider).contains(received.rideId)) {
          return;
        }
        try {
          final ride = Ride.fromJson(received.payload);
          _ref
              .read(surfacedRideIdsProvider.notifier)
              .update((ids) => {...ids, ride.id});
          _ref.read(incomingRideRequestProvider.notifier).state = null;
          _ref.read(incomingRideRequestProvider.notifier).state = ride;
          _ref.read(navBadgeProvider.notifier).increment('/home');
        } catch (error) {
          debugPrint('[FCM] foreground ride offer parse failed: $error');
        }
        return;
      }
      if (isActionableJobOfferPayload(
        type,
        Map<String, dynamic>.from(message.data),
      )) {
        final expectedSession = _ref.read(currentAuthSessionIdentityProvider);
        if (expectedSession == null) return;
        final received = await acknowledgeJobOffer(
          payload: Map<String, dynamic>.from(message.data),
          jobs: _ref.read(jobServiceProvider),
        );
        if (received == null) {
          debugPrint('[FCM] foreground job offer receipt failed');
          return;
        }
        if (_ref.read(currentAuthSessionIdentityProvider) != expectedSession) {
          debugPrint('[FCM] dropped job offer after account/session change');
          return;
        }
        // Re-read after the receipt await so a concurrent socket copy that
        // won the race is treated as the single surface owner.
        final previouslySurfaced =
            _ref.read(surfacedJobIdsProvider).contains(received.jobId);
        final previousExact =
            _ref.read(lastJobOfferIdByJobProvider)[received.jobId];
        if (received.hasExactReceipt) {
          _ref.read(jobOfferIdByJobProvider.notifier).update(
                (offers) => {
                  ...offers,
                  received.jobId: received.offerId!,
                },
              );
          _ref.read(lastJobOfferIdByJobProvider.notifier).update(
                (offers) => {
                  ...offers,
                  received.jobId: received.offerId!,
                },
              );
          final deadline = received.decisionExpiresAt;
          if (deadline != null) {
            _ref.read(jobOfferDeadlineByJobProvider.notifier).update(
                  (deadlines) => {
                    ...deadlines,
                    received.jobId: deadline,
                  },
                );
          }
          if (previousExact != received.offerId) {
            _ref.read(jobOfferDismissalProvider.notifier).state = null;
          }
        }
        final disposition = jobOfferSurfaceDisposition(
          jobAlreadySurfaced: previouslySurfaced,
          lastExactOfferId: previousExact,
          incomingOfferId: received.offerId,
        );
        if (disposition == JobOfferSurfaceDisposition.ignoreDuplicate) {
          return;
        }
        try {
          final job = Job.fromJson(received.payload);
          if (disposition == JobOfferSurfaceDisposition.enrichExisting) {
            _ref.read(pendingIncomingJobsProvider.notifier).enqueue(job);
            return;
          }
          _ref
              .read(surfacedJobIdsProvider.notifier)
              .update((ids) => {...ids, job.id});
          _ref.read(pendingIncomingJobsProvider.notifier).enqueue(job);
          if (_ref.read(visibleJobModalIdProvider) == job.id) return;
          _ref.read(incomingJobRequestProvider.notifier).state = null;
          _ref.read(incomingJobRequestProvider.notifier).state = job;
          _ref.read(navBadgeProvider.notifier).increment('/home');
        } catch (error) {
          debugPrint('[FCM] foreground job offer parse failed: $error');
          await _renderFromRemote(message, dataOverride: received.payload);
        }
        return;
      }
      if (type == NotificationPayload.typeRideCancelled) {
        final rideId = (message.data[NotificationPayload.keyRideId] ??
                message.data['ride_id'])
            ?.toString();
        final cleared =
            _ref.read(activeRideProvider.notifier).clearRideIfMatches(rideId);
        if (cleared) {
          _ref.read(goRouterProvider).go('/home');
        }
        // Keep the cancellation notification visible as confirmation even
        // though matching local ride state has already been reconciled.
        await _renderFromRemote(message);
        return;
      }
      if (type == NotificationPayload.typeNewMessage) {
        final bookingId =
            (message.data[NotificationPayload.keyBookingId] as String?) ??
                (message.data[NotificationPayload.keyJobId] as String?) ??
                (message.data[NotificationPayload.keyRideId] as String?);
        if (_isOnChatScreenFor(bookingId)) {
          debugPrint(
            '[FCM] foreground new_message — on chat screen, suppressing',
          );
          return;
        }
        await _renderFromRemote(message);
        return;
      }
      // Incoming-request types are handled foreground by
      // IncomingRequestListener (modal for jobs, full-screen for rides)
      // backed by the socket. Rendering the local heads-up banner on
      // top would stack a second alert with full-screen intent over
      // the in-app modal — silencing the looping ringtone gets messy
      // when two alert paths fire for the same booking.
      if (type != NotificationPayload.typeCallIncoming &&
          NotificationPayload.persistentRequestTypes.contains(type)) {
        if (_ref.read(socketConnectedProvider)) {
          debugPrint(
            '[FCM] foreground $type — socket will surface in-app request',
          );
          return;
        }
        debugPrint(
          '[FCM] foreground $type — socket offline, rendering fallback',
        );
      }
      await _renderFromRemote(message);
    });

    // User tapped a push while the app was backgrounded → resumed.
    _openedMessageSub ??= FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      debugPrint(
        '[FCM] opened from background: type=${message.data['type']} '
        'keys=${message.data.keys.toList()}',
      );
      final payload = Map<String, dynamic>.from(message.data);
      unawaited(_markNotificationRead(payload));
      final handler = onTapMessage;
      if (handler != null) unawaited(handler(payload));
    });

    // Cold-start tap: app was terminated, user tapped a push to open it.
    //
    // This plugin call has been observed hanging on a real iOS device. FCM
    // handler setup must not remain permanently "initialising" because Go
    // Online also verifies notification reachability. Pending-request recovery
    // remains the fallback when the cold-start payload cannot be read in time.
    RemoteMessage? initialMessage;
    try {
      initialMessage = await _fcm.getInitialMessage().timeout(
            const Duration(seconds: 5),
          );
    } catch (error) {
      debugPrint('[FCM] initial message lookup unavailable: $error');
    }
    if (initialMessage != null) {
      debugPrint(
        '[FCM] initial message: type=${initialMessage.data['type']} '
        'keys=${initialMessage.data.keys.toList()}',
      );
      final payload = Map<String, dynamic>.from(initialMessage.data);
      // Defer until the router is ready to avoid navigating before the
      // first frame. Correlate the in-app read only after navigation has
      // mounted an authenticated shell/inbox listener; otherwise an
      // auto-disposed cold-start notifier could disappear mid-fetch.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        final handler = onTapMessage;
        unawaited(() async {
          if (handler != null) await handler(payload);
          await _markNotificationRead(payload);
        }());
      });
    }

    // Defense in depth: the auth bridge can fire before Firebase setup has
    // finished. Kick token sync again after initialisation; registration is
    // idempotent, and display permission is checked contextually at Go Online.
    final authState = _ref.read(authControllerProvider);
    if (authState is AuthAuthenticated) {
      unawaited(syncToken());
    }
    _initialised = true;
    debugPrint('[FCM] initialisation complete');
  }

  /// Marks the persisted in-app sibling represented by a tray payload read.
  ///
  /// Multi-channel sends create a different row per delivery channel, so the
  /// push payload's `notificationId` identifies the push row and cannot clear
  /// the inbox badge. Correlation is deliberately restricted to campaign ids
  /// or allowlisted entity ids plus a known event type. The notifier performs
  /// the PATCH only after it has found that safe in-app match.
  Future<void> _markNotificationRead(Map<String, dynamic> payload) async {
    try {
      final currentIdentity = _ref.read(currentAuthSessionIdentityProvider);
      final identity = currentIdentity ??
          (await _ref.read(appTokenStorageProvider).readTokenSnapshot())
              .identity;
      if (identity == null) return;

      final store = _ref.read(pendingProviderNotificationReadStoreProvider);
      final pending = await store.save(payload, owner: identity);
      if (pending == null) {
        debugPrint('[FCM] tray payload has no safe read correlation');
        return;
      }

      // A cold-start callback can precede authenticated shell/provider
      // creation. The sanitized receipt is already durable; let the shell
      // consume it once it owns the auto-dispose inbox instead of creating a
      // transient notifier here and risking a use-after-dispose completion.
      if (currentIdentity == null || !_ref.exists(providerNotifsProvider)) {
        return;
      }

      await _ref.read(consumePendingProviderNotificationReadProvider)();
    } catch (_) {
      debugPrint(
        '[FCM] deferred in-app read acknowledgement for tray payload '
        'type=${payload[NotificationPayload.keyType]}',
      );
    }
  }

  /// Fetch the FCM token and POST it to the backend so we can receive
  /// pushes. Call once the user is authenticated (needs JWT on the Dio
  /// client). Also subscribes to token refresh events.
  Future<String?> ensureOnlineNotificationReachability({
    bool requestPermissionIfNeeded = true,
  }) async {
    if (!_ref.read(firebaseReadyProvider)) {
      return 'Notifications are still starting. Check your connection and try again.';
    }

    try {
      // Permission and token authority come directly from the operating system
      // and Firebase Messaging. Do not await the separate message-handler
      // initialisation path here: cold-start payload recovery can be slow or
      // unavailable, but that must never suppress the OS permission prompt or
      // falsely report a Settings problem.
      if (!_initialised) {
        unawaited(
          init().catchError(
            (Object error) =>
                debugPrint('[FCM] deferred handler init failed: $error'),
          ),
        );
      }

      var settings = await _fcm.getNotificationSettings().timeout(
            const Duration(seconds: 5),
          );
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined &&
          requestPermissionIfNeeded) {
        settings = await _fcm
            .requestPermission(alert: true, badge: true, sound: true)
            .timeout(const Duration(seconds: 15));
      }
      if (!notificationAuthorizationAllowsOnline(
        settings.authorizationStatus,
      )) {
        return 'Enable notifications in Settings before going online so you can receive requests.';
      }

      if (Platform.isIOS) {
        final apnsToken = await _fcm.getAPNSToken().timeout(
              const Duration(seconds: 5),
            );
        if (apnsToken == null || apnsToken.isEmpty) {
          return 'This device is not ready for notifications yet. Check your connection and try again.';
        }
      }

      final token = await _fcm.getToken().timeout(const Duration(seconds: 8));
      if (token == null || token.isEmpty) {
        return 'This device could not register for notifications. Check your connection and try again.';
      }
      final registered = await _register(
        token,
      ).timeout(const Duration(seconds: 15));
      if (!registered) {
        return 'MyShop could not register this device for requests. Check your connection and try again.';
      }
      return null;
    } catch (error) {
      debugPrint('[FCM] online reachability check failed: $error');
      return 'MyShop could not verify notification access. Check Settings and your connection, then try again.';
    }
  }

  Future<void> syncToken() async {
    debugPrint('[FCM] syncToken() entered');
    final operationEpoch = ++_lifecycleEpoch;
    final identity =
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot()).identity;
    if (identity == null || operationEpoch != _lifecycleEpoch) return;

    // Register the token-refresh listener FIRST. On iOS, APNs registration
    // on a fresh install can take longer than our initial retry window.
    // If we exhaust retries here, the FCM token still arrives later via
    // onTokenRefresh — and we need the listener already wired so the
    // _register call fires the moment the token shows up.
    final previousTokenRefreshSub = _tokenRefreshSub;
    await previousTokenRefreshSub?.cancel();
    if (_tokenRefreshSub == previousTokenRefreshSub) {
      _tokenRefreshSub = null;
    }
    if (!await _ownsLifecycle(operationEpoch, identity)) return;
    _tokenRefreshSub = _fcm.onTokenRefresh.listen(
      (token) => _register(token, expectedIdentity: identity),
    );
    if (Platform.isIOS) {
      final previousVoipSub = _voipEventSub;
      await previousVoipSub?.cancel();
      if (_voipEventSub == previousVoipSub) {
        _voipEventSub = null;
      }
      if (!await _ownsLifecycle(operationEpoch, identity)) return;
      _wireVoipBridge(identity);
      unawaited(_syncVoipTokenOnce(expectedIdentity: identity));
      final previousLiveActivitySub = _liveActivityEventSub;
      await previousLiveActivitySub?.cancel();
      if (_liveActivityEventSub == previousLiveActivitySub) {
        _liveActivityEventSub = null;
      }
      if (!await _ownsLifecycle(operationEpoch, identity)) return;
      _wireLiveActivityBridge(identity);
      // ActivityKit may have produced and persisted its token before Flutter
      // attached. Do not rely on a new native event being emitted: snapshots
      // are idempotent, and the later successful FCM registration repeats the
      // sync after the backend has a current device row to bind against.
      unawaited(_syncLiveActivityTokensOnce(expectedIdentity: identity));
    }

    // iOS: FCM derives its token from the APNs device token. On cold
    // start `getToken()` throws `apns-token-not-set` if called before
    // APNs has handed back a token. Wait first; if it never arrives
    // within our budget, return and let onTokenRefresh catch it.
    if (Platform.isIOS) {
      final apnsReady = await _awaitApnsToken();
      if (!apnsReady || !await _ownsLifecycle(operationEpoch, identity)) {
        debugPrint(
          '[FCM] APNs not ready within budget — '
          'onTokenRefresh will register the token when it arrives',
        );
        return;
      }
    }

    String? token;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        token = await _fcm.getToken();
        if (token != null) break;
      } catch (e) {
        // Swallow the iOS `apns-token-not-set` race — the listener above
        // covers the eventually-arrives case. Logging only.
        debugPrint('[FCM] getToken threw (attempt $attempt/3): $e');
      }
      debugPrint('[FCM] getToken null (attempt $attempt/3) — retrying');
      await Future<void>.delayed(Duration(seconds: attempt * 2));
      if (!await _ownsLifecycle(operationEpoch, identity)) return;
    }
    if (token == null) {
      debugPrint(
        '[FCM] initial getToken exhausted retries — '
        'relying on onTokenRefresh',
      );
      return;
    }
    debugPrint('[FCM] obtained device token');
    await _register(token, expectedIdentity: identity);
  }

  Future<bool> _ownsLifecycle(
    int operationEpoch,
    AuthSessionIdentity identity,
  ) async {
    if (operationEpoch != _lifecycleEpoch) return false;
    final current =
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot()).identity;
    return operationEpoch == _lifecycleEpoch && current == identity;
  }

  /// Returns true if APNs token arrived within the retry budget, false
  /// otherwise. False does NOT mean "never" — onTokenRefresh will still
  /// catch a late arrival.
  Future<bool> _awaitApnsToken() async {
    // 10 attempts with linear backoff = up to ~55s total. First APNs
    // registration on a freshly installed dev build can easily take
    // 20–40s, and the previous 15s budget routinely undershot.
    const maxAttempts = 10;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final apns = await _fcm.getAPNSToken();
      if (apns != null) {
        debugPrint('[FCM] APNs token ready on attempt $attempt');
        return true;
      }
      debugPrint(
        '[FCM] APNs token not yet available (attempt $attempt/$maxAttempts)',
      );
      await Future<void>.delayed(Duration(seconds: attempt));
    }
    return false;
  }

  Future<bool> _register(
    String token, {
    AuthSessionIdentity? expectedIdentity,
  }) async {
    final identity = expectedIdentity ??
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot()).identity;
    if (identity == null ||
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot())
                .identity !=
            identity) {
      debugPrint('[FCM] no active exact session — skipping registration');
      return false;
    }
    final role = identity.role;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _ref.read(apiNotificationServiceProvider).registerDevice(
              fcmToken: token,
              platform: _platform,
              role: role,
              offerReceiptVersion: providerOfferReceiptCapabilityVersion,
              expectedIdentity: identity,
            );
        await _publishDeviceRegistrationOwner(identity);
        debugPrint('[FCM] token registered (role=$role, attempt $attempt)');
        if (Platform.isIOS) {
          await _syncLiveActivityTokensOnce(expectedIdentity: identity);
        }
        return true;
      } on ApiException catch (e) {
        // A max-v2 backend predates exact artisan job receipts. Retain its
        // ride/ActivityKit capability during rollout, then omit the marker
        // only for a still older backend that rejects the field entirely.
        if (isOfferReceiptCapabilityValidationError(e)) {
          try {
            await _ref.read(apiNotificationServiceProvider).registerDevice(
                  fcmToken: token,
                  platform: _platform,
                  role: role,
                  offerReceiptVersion:
                      legacyProviderOfferReceiptCapabilityVersion,
                  expectedIdentity: identity,
                );
            await _publishDeviceRegistrationOwner(identity);
            debugPrint(
              '[FCM] token registered with legacy v2 receipt capability; v3 job receipts will sync after backend upgrade',
            );
            return true;
          } on ApiException catch (v2Error) {
            if (isOfferReceiptCapabilityValidationError(v2Error)) {
              try {
                await _ref.read(apiNotificationServiceProvider).registerDevice(
                      fcmToken: token,
                      platform: _platform,
                      role: role,
                      offerReceiptVersion: null,
                      expectedIdentity: identity,
                    );
                await _publishDeviceRegistrationOwner(identity);
                debugPrint(
                  '[FCM] token registered against a pre-receipt backend; capability will sync after backend upgrade',
                );
                return true;
              } catch (legacyError) {
                debugPrint(
                  '[FCM] pre-receipt backend registration fallback failed: $legacyError',
                );
              }
            } else {
              debugPrint(
                '[FCM] v2 receipt registration fallback failed: $v2Error',
              );
            }
          } catch (legacyError) {
            debugPrint(
              '[FCM] v2 receipt registration fallback failed: $legacyError',
            );
          }
        }
        debugPrint('[FCM] register attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      } catch (e) {
        debugPrint('[FCM] register attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    debugPrint('[FCM] register exhausted retries — token NOT registered');
    return false;
  }

  Future<void> _publishDeviceRegistrationOwner(
    AuthSessionIdentity identity,
  ) async {
    if ((await _ref.read(appTokenStorageProvider).readTokenSnapshot())
            .identity ==
        identity) {
      _deviceRegistrationIdentity = identity;
    }
  }

  void _wireVoipBridge(AuthSessionIdentity identity) {
    _voipEventSub ??= VoipCallBridgeService.instance.events.listen((event) {
      switch (event.type) {
        case VoipCallBridgeEventType.tokenUpdated:
          final token = event.token;
          if (token != null && token.isNotEmpty) {
            unawaited(_registerVoipToken(token, expectedIdentity: identity));
          }
        case VoipCallBridgeEventType.tokenInvalidated:
          unawaited(
            _unregisterVoipToken(event.token, expectedIdentity: identity),
          );
        case VoipCallBridgeEventType.incomingCall:
          debugPrint('[VoIP] incoming call bridge event: ${event.payload}');
          unawaited(_trackIncomingCall(event));
        case VoipCallBridgeEventType.callAccepted:
          unawaited(_handleVoipCallAccepted(event));
        case VoipCallBridgeEventType.callDeclined:
          unawaited(_handleVoipCallDeclined(event));
        case VoipCallBridgeEventType.callEnded:
          unawaited(_handleVoipCallEnded(event));
        case VoipCallBridgeEventType.unknown:
          debugPrint('[VoIP] bridge event: ${event.type} ${event.payload}');
      }
    });
  }

  void _openAndroidIncomingCall(Map<String, dynamic> payload) {
    final callId = payload[NotificationPayload.keyCallId]?.toString();
    if (callId == null || callId.isEmpty) return;
    _ref.read(goRouterProvider).go('/calls/$callId');
  }

  String _routeAfterCall(AppCallSession session) {
    return switch (session.bookingType) {
      'ride' => '/active-ride',
      'artisan_job' ||
      'job' when session.bookingId.isNotEmpty =>
        '/active-job?jobId=${Uri.encodeQueryComponent(session.bookingId)}',
      _ => '/home',
    };
  }

  Future<void> _trackIncomingCall(VoipCallBridgeEvent event) async {
    final callId = event.callId;
    if (callId == null || callId.isEmpty) return;
    final socket = _ref.read(appCallSocketServiceProvider);
    _incomingCallStateSub ??= socket.sessionStream.listen((session) {
      if (!_trackedIncomingCallIds.contains(session.callId) ||
          !session.isTerminal) {
        return;
      }
      _trackedIncomingCallIds.remove(session.callId);
      socket.leaveCall(session.callId);
      unawaited(VoipCallBridgeService.instance.endCall(session.callId));
      debugPrint(
        '[VoIP] remote ${session.status} dismissed CallKit: ${session.callId}',
      );
    });
    if (_trackedIncomingCallIds.add(callId)) {
      await socket.joinCall(callId);
      debugPrint('[VoIP] joined call socket before answer: $callId');
    }
  }

  void _stopTrackingIncomingCall(String callId) {
    if (!_trackedIncomingCallIds.remove(callId)) return;
    _ref.read(appCallSocketServiceProvider).leaveCall(callId);
  }

  Future<void> _handleVoipCallAccepted(VoipCallBridgeEvent event) async {
    final callId = event.callId;
    if (callId == null || callId.isEmpty) {
      debugPrint('[VoIP] callAccepted missing callId: ${event.payload}');
      return;
    }
    final router = _ref.read(goRouterProvider);
    router.go('/calls/$callId');
    try {
      final session = await _retryVoipAction(
        () => _ref.read(appCallServiceProvider).acceptCall(callId),
      );
      router.go('/calls/$callId', extra: session);
      await VoipCallBridgeService.instance.acknowledgeCallAction(
        event.actionId,
      );
    } catch (error) {
      debugPrint('[VoIP] accept failed for $callId: $error');
      try {
        await _ref.read(appCallServiceProvider).endCall(callId);
      } catch (cleanupError) {
        debugPrint('[VoIP] accept recovery backend end failed: $cleanupError');
      }
      try {
        await VoipCallBridgeService.instance.endCall(callId);
      } catch (cleanupError) {
        debugPrint('[VoIP] accept recovery CallKit end failed: $cleanupError');
      }
      _stopTrackingIncomingCall(callId);
      try {
        await VoipCallBridgeService.instance.acknowledgeCallAction(
          event.actionId,
        );
      } catch (cleanupError) {
        debugPrint('[VoIP] accept recovery acknowledge failed: $cleanupError');
      }
      router.go('/home');
    }
  }

  Future<void> _handleVoipCallDeclined(VoipCallBridgeEvent event) async {
    final callId = event.callId;
    if (callId == null || callId.isEmpty) {
      debugPrint('[VoIP] callDeclined missing callId: ${event.payload}');
      return;
    }
    try {
      var session = await _retryVoipAction(
        () => _ref.read(appCallServiceProvider).declineCall(callId),
      );
      if (!session.isTerminal) {
        debugPrint(
          '[VoIP] decline raced ${session.status}; ending call: $callId',
        );
        session = await _retryVoipAction(
          () => _ref.read(appCallServiceProvider).endCall(callId),
        );
      }
      _stopTrackingIncomingCall(callId);
      await VoipCallBridgeService.instance.endCall(callId);
      _ref.read(goRouterProvider).go(_routeAfterCall(session));
      await VoipCallBridgeService.instance.acknowledgeCallAction(
        event.actionId,
      );
    } catch (error) {
      debugPrint('[VoIP] decline failed for $callId: $error');
    }
  }

  Future<void> _handleVoipCallEnded(VoipCallBridgeEvent event) async {
    final callId = event.callId;
    if (callId == null || callId.isEmpty) {
      debugPrint('[VoIP] callEnded missing callId: ${event.payload}');
      return;
    }
    try {
      final session = await _retryVoipAction(
        () => _ref.read(appCallServiceProvider).endCall(callId),
      );
      _stopTrackingIncomingCall(callId);
      _ref.read(goRouterProvider).go(_routeAfterCall(session));
      await VoipCallBridgeService.instance.acknowledgeCallAction(
        event.actionId,
      );
    } catch (error) {
      debugPrint('[VoIP] end failed for $callId: $error');
    }
  }

  Future<T> _retryVoipAction<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await action();
      } catch (error) {
        lastError = error;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    }
    throw lastError!;
  }

  Future<void> _syncVoipTokenOnce({
    required AuthSessionIdentity expectedIdentity,
  }) async {
    final token = await VoipCallBridgeService.instance.getVoipToken();
    if (token == null || token.isEmpty) return;
    await _registerVoipToken(token, expectedIdentity: expectedIdentity);
  }

  Future<void> _registerVoipToken(
    String token, {
    required AuthSessionIdentity expectedIdentity,
  }) async {
    if ((await _ref.read(appTokenStorageProvider).readTokenSnapshot())
            .identity !=
        expectedIdentity) {
      debugPrint('[VoIP] no active session — skipping token registration');
      return;
    }

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _ref.read(apiNotificationServiceProvider).registerVoipDevice(
              voipToken: token,
              expectedIdentity: expectedIdentity,
            );
        if ((await _ref.read(appTokenStorageProvider).readTokenSnapshot())
                .identity ==
            expectedIdentity) {
          _voipRegistrationIdentity = expectedIdentity;
        }
        debugPrint(
          '[VoIP] token registered '
          '(role=${expectedIdentity.role}, attempt $attempt)',
        );
        return;
      } catch (e) {
        debugPrint('[VoIP] register attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    debugPrint('[VoIP] register exhausted retries — token NOT registered');
  }

  Future<void> _unregisterVoipToken(
    String? token, {
    AuthSessionIdentity? expectedIdentity,
  }) async {
    if (expectedIdentity == null) {
      debugPrint('[VoIP] no owned session — skipping token unregister');
      return;
    }
    try {
      await _ref.read(apiNotificationServiceProvider).unregisterVoipDevice(
            voipToken: token,
            expectedIdentity: expectedIdentity,
          );
      if (_voipRegistrationIdentity == expectedIdentity) {
        _voipRegistrationIdentity = null;
      }
      debugPrint('[VoIP] token unregistered');
    } catch (e) {
      debugPrint('[VoIP] unregister failed: $e');
    }
  }

  void _wireLiveActivityBridge(AuthSessionIdentity identity) {
    _liveActivityEventSub ??= LiveActivityService.instance.events.listen(
      (event) => unawaited(
        _handleLiveActivityEvent(event, expectedIdentity: identity),
      ),
      onError: (Object error) {
        debugPrint('[LiveActivity] native event stream failed: $error');
      },
    );
  }

  Future<void> _handleLiveActivityEvent(
    LiveActivityBridgeEvent event, {
    required AuthSessionIdentity expectedIdentity,
  }) async {
    switch (event.type) {
      case LiveActivityBridgeEventType.pushToStartToken:
        final token = event.token;
        if (token != null && token.isNotEmpty) {
          await _registerLiveActivityDevice(
            token,
            expectedIdentity: expectedIdentity,
          );
        }
      case LiveActivityBridgeEventType.activityUpdateToken:
        final activity = event.activity;
        if (activity != null) {
          await _registerLiveActivity(
            activity,
            expectedIdentity: expectedIdentity,
          );
        }
      case LiveActivityBridgeEventType.activityEnded:
        final activity = event.activity;
        if (activity != null) {
          await _unregisterLiveActivity(
            activity,
            expectedIdentity: expectedIdentity,
          );
        }
      case LiveActivityBridgeEventType.activitiesEnabled:
        if (event.activitiesEnabled == false) {
          await _unregisterLiveActivityDevice(
            expectedIdentity: expectedIdentity,
          );
        } else {
          await _syncLiveActivityTokensOnce(expectedIdentity: expectedIdentity);
        }
      case LiveActivityBridgeEventType.unknown:
        debugPrint('[LiveActivity] ignored unknown native event');
    }
  }

  Future<void> _syncLiveActivityTokensOnce({
    required AuthSessionIdentity expectedIdentity,
  }) async {
    final state = await LiveActivityService.instance.getState();
    if (state.activitiesEnabled == false) {
      await _unregisterLiveActivityDevice(expectedIdentity: expectedIdentity);
      return;
    }
    final pushToStartToken = state.pushToStartToken;
    if (pushToStartToken != null && pushToStartToken.isNotEmpty) {
      await _registerLiveActivityDevice(
        pushToStartToken,
        expectedIdentity: expectedIdentity,
      );
    }
    for (final activity in state.activities) {
      if (activity.updateToken == null || activity.updateToken!.isEmpty) {
        continue;
      }
      await _registerLiveActivity(activity, expectedIdentity: expectedIdentity);
    }
  }

  Future<void> _registerLiveActivityDevice(
    String token, {
    required AuthSessionIdentity expectedIdentity,
  }) async {
    if ((await _ref.read(appTokenStorageProvider).readTokenSnapshot())
            .identity !=
        expectedIdentity) {
      debugPrint(
        '[LiveActivity] no active session — skipping token registration',
      );
      return;
    }
    final registered = await _retryLiveActivityRegistration(
      label: 'push-to-start',
      action: () =>
          _ref.read(apiNotificationServiceProvider).registerLiveActivityDevice(
                pushToStartToken: token,
                expectedIdentity: expectedIdentity,
              ),
    );
    if (registered &&
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot())
                .identity ==
            expectedIdentity) {
      _liveActivityRegistrationIdentity = expectedIdentity;
    }
  }

  Future<void> _unregisterLiveActivityDevice({
    String? token,
    AuthSessionIdentity? expectedIdentity,
  }) async {
    if (expectedIdentity == null) {
      debugPrint(
        '[LiveActivity] no owned session — skipping device unregister',
      );
      return;
    }
    try {
      await _ref
          .read(apiNotificationServiceProvider)
          .unregisterLiveActivityDevice(
            pushToStartToken: token,
            expectedIdentity: expectedIdentity,
          );
      if (_liveActivityRegistrationIdentity == expectedIdentity) {
        _liveActivityRegistrationIdentity = null;
      }
      debugPrint('[LiveActivity] device unregistered');
    } catch (error) {
      debugPrint('[LiveActivity] device unregister failed: $error');
    }
  }

  Future<void> _registerLiveActivity(
    LiveActivityRegistration activity, {
    required AuthSessionIdentity expectedIdentity,
  }) async {
    final updateToken = activity.updateToken;
    if (updateToken == null || updateToken.isEmpty) return;
    if ((await _ref.read(appTokenStorageProvider).readTokenSnapshot())
            .identity !=
        expectedIdentity) {
      debugPrint('[LiveActivity] no active session — skipping activity token');
      return;
    }
    final registered = await _retryLiveActivityRegistration(
      label: 'activity ${activity.activityId}',
      action: () =>
          _ref.read(apiNotificationServiceProvider).registerLiveActivity(
                activityId: activity.activityId,
                updateToken: updateToken,
                offerId: activity.offerId,
                requestType: activity.requestType,
                requestId: activity.requestId,
                expiresAt: activity.expiresAt,
                expectedIdentity: expectedIdentity,
              ),
    );
    if (registered &&
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot())
                .identity ==
            expectedIdentity) {
      _liveActivityRegistrationIdentity = expectedIdentity;
    }
  }

  Future<void> _unregisterLiveActivity(
    LiveActivityRegistration activity, {
    AuthSessionIdentity? expectedIdentity,
  }) async {
    if (expectedIdentity == null) {
      debugPrint(
        '[LiveActivity] no owned session — skipping activity unregister',
      );
      return;
    }
    try {
      await _ref.read(apiNotificationServiceProvider).unregisterLiveActivity(
            activityId: activity.activityId,
            updateToken: activity.updateToken,
            expectedIdentity: expectedIdentity,
          );
      debugPrint('[LiveActivity] unregistered ${activity.activityId}');
    } catch (error) {
      debugPrint(
        '[LiveActivity] unregister ${activity.activityId} failed: $error',
      );
    }
  }

  Future<bool> _retryLiveActivityRegistration({
    required String label,
    required Future<void> Function() action,
  }) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await action();
        debugPrint('[LiveActivity] $label registered (attempt $attempt)');
        return true;
      } catch (error) {
        debugPrint(
          '[LiveActivity] $label register attempt $attempt/3 failed: $error',
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    return false;
  }

  String get _platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// True when the active GoRouter location is the chat screen.
  /// Used by the foreground new_message handler so a banner only
  /// suppresses when the driver is already reading a chat — every
  /// other screen (home, earnings, active-ride) lets the banner
  /// surface so the driver doesn't miss the message.
  ///
  /// We don't disambiguate by bookingId here (the `extra` map isn't
  /// reachable via the public GoRouter API on every version). A driver
  /// who happens to be on chat A while a message lands for chat B
  /// will miss the banner — acceptable trade-off vs. banner-bombing
  /// while they're actively typing.
  // ignore: unused_element
  bool _isOnChatScreenFor(String? bookingId) {
    try {
      final router = _ref.read(goRouterProvider);
      final matches = router.routerDelegate.currentConfiguration.matches;
      if (matches.isEmpty) return false;
      return matches.last.matchedLocation == '/chat';
    } catch (_) {
      return false;
    }
  }

  /// Remove backend registration + cancel listeners. Call on logout so the
  /// user's next account on this device gets its own fresh token binding.
  Future<void> dispose() async {
    final operationEpoch = ++_lifecycleEpoch;
    final deviceOwner = _deviceRegistrationIdentity;
    final voipOwner = _voipRegistrationIdentity;
    final liveActivityOwner = _liveActivityRegistrationIdentity;
    final tokenRefreshSub = _tokenRefreshSub;
    await tokenRefreshSub?.cancel();
    if (_tokenRefreshSub == tokenRefreshSub) {
      _tokenRefreshSub = null;
    }
    if (operationEpoch != _lifecycleEpoch) return;
    await _unregisterVoipToken(
      await VoipCallBridgeService.instance.getVoipToken(),
      expectedIdentity: voipOwner,
    );
    if (operationEpoch != _lifecycleEpoch) return;
    final voipEventSub = _voipEventSub;
    await voipEventSub?.cancel();
    if (_voipEventSub == voipEventSub) {
      _voipEventSub = null;
    }
    if (operationEpoch != _lifecycleEpoch) return;
    if (Platform.isIOS) {
      final liveActivityState = await LiveActivityService.instance.getState();
      if (operationEpoch != _lifecycleEpoch) return;
      await _unregisterLiveActivityDevice(
        token: liveActivityState.pushToStartToken,
        expectedIdentity: liveActivityOwner,
      );
    }
    if (operationEpoch != _lifecycleEpoch) return;
    final liveActivityEventSub = _liveActivityEventSub;
    await liveActivityEventSub?.cancel();
    if (_liveActivityEventSub == liveActivityEventSub) {
      _liveActivityEventSub = null;
    }
    if (operationEpoch != _lifecycleEpoch) return;
    final currentBeforeEndAll =
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot()).identity;
    if (currentBeforeEndAll != null && currentBeforeEndAll != deviceOwner) {
      return;
    }
    await LiveActivityService.instance.endAll();
    if (operationEpoch != _lifecycleEpoch) return;
    await _incomingCallStateSub?.cancel();
    _incomingCallStateSub = null;
    final socket = _ref.read(appCallSocketServiceProvider);
    for (final callId in _trackedIncomingCallIds) {
      socket.leaveCall(callId);
    }
    _trackedIncomingCallIds.clear();
    final currentIdentity =
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot()).identity;
    if (operationEpoch != _lifecycleEpoch ||
        (currentIdentity != null && currentIdentity != deviceOwner)) {
      return;
    }
    try {
      await _fcm.deleteToken();
      if (_deviceRegistrationIdentity == deviceOwner) {
        _deviceRegistrationIdentity = null;
      }
    } catch (_) {
      // best-effort
    }
  }
}

/// Flips only after Firebase.initializeApp succeeds. ProviderApp uses this to
/// avoid constructing FirebaseMessaging while Firebase is still starting.
final firebaseReadyProvider = StateProvider<bool>((_) => false);

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref);
});

typedef OnlineNotificationReachabilityCheck = Future<String?> Function();

final onlineNotificationReachabilityCheckProvider =
    Provider<OnlineNotificationReachabilityCheck>((ref) {
  final fcm = ref.read(fcmServiceProvider);
  return fcm.ensureOnlineNotificationReachability;
});

/// BR-32 relaunch recovery must never make an OS permission prompt appear on
/// its own. A prior Online intent can reuse an existing notification grant,
/// but a missing grant leaves the provider Offline with actionable copy until
/// they explicitly tap Go Online.
final onlineNotificationRestoreReachabilityCheckProvider =
    Provider<OnlineNotificationReachabilityCheck>((ref) {
  final fcm = ref.read(fcmServiceProvider);
  return () => fcm.ensureOnlineNotificationReachability(
        requestPermissionIfNeeded: false,
      );
});

/// Watches the auth state and synchronises the FCM token with the backend
/// as soon as the user reaches `AuthAuthenticated`. On logout it clears
/// the device token so the next account on this device registers a fresh
/// binding.
///
/// Must be watched once at app start (e.g. `container.read(...)` in main)
/// so it stays subscribed.
final fcmAuthBridgeProvider = Provider<void>((ref) {
  final fcm = ref.read(fcmServiceProvider);
  ref.listen<AuthState>(authControllerProvider, (previous, next) {
    debugPrint('[FCM-bridge] auth state = ${next.runtimeType}');
    if (next is AuthAuthenticated) {
      debugPrint('[FCM-bridge] firing syncToken()');
      unawaited(fcm.syncToken());
      return;
    }
    // Initial cold-start unauthenticated state is not a logout. Only tear down
    // native token listeners and Live Activities after an authenticated
    // session actually transitions to unauthenticated.
    if (previous is AuthAuthenticated && next is AuthUnauthenticated) {
      debugPrint('[FCM-bridge] firing dispose() (logout)');
      unawaited(fcm.dispose());
    }
  }, fireImmediately: true);
});

/// Seeds the provider dashboard, waits until it is the router's actual
/// configuration, then places the tray destination above it. `go()` changes
/// route information before the Navigator pages rebuild; a same-turn `push()`
/// can otherwise use the stale shell stack and leave Back broken.
@visibleForTesting
Future<void> openProviderTrayDestination(
  GoRouter router,
  String destination, {
  Object? extra,
}) async {
  final stack = providerSystemTrayNavigationStack(destination);
  router.go(stack.first);
  if (stack.length == 1) return;

  final baseReady = await _waitForProviderTrayBase(router, stack.first);
  if (!baseReady) {
    debugPrint(
      '[FCM-tap] tray navigation base was redirected away from '
      '${stack.first}; destination deferred',
    );
    return;
  }
  unawaited(router.push<void>(stack.last, extra: extra));
}

Future<bool> _waitForProviderTrayBase(
  GoRouter router,
  String expectedPath,
) async {
  bool isReady() =>
      router.routerDelegate.currentConfiguration.uri.path == expectedPath;
  if (isReady()) return true;

  final ready = Completer<bool>();
  late VoidCallback listener;
  Timer? timeout;
  listener = () {
    if (isReady() && !ready.isCompleted) ready.complete(true);
  };
  router.routerDelegate.addListener(listener);
  timeout = Timer(const Duration(seconds: 10), () {
    if (!ready.isCompleted) ready.complete(false);
  });
  // Close the race between the first check and listener registration.
  listener();

  try {
    return await ready.future;
  } finally {
    timeout.cancel();
    router.routerDelegate.removeListener(listener);
  }
}

/// Wires FCM notification taps into GoRouter navigation.
///
/// Routing table:
///   job_request (+ jobId)       → fetch job → /job-request
///   ride_request                → /home  (socket-driven modal surfaces)
///   bid_accepted (+ jobId)      → /active-job  (artisan can start)
///   bid_rejected                → /home
///   supplement_approved         → /active-job
///   supplement_rejected         → /active-job
///   job_cancelled / ride_cancelled → /home
///   job_confirmed_complete      → /home  (payout hit)
///   ride_settled                → /earnings
///   payment_received            → /earnings
///   new_message (+ jobId/rideId)→ /messages
///   everything else             → /home
///
/// Must be read once at app start AFTER the router has been created so
/// `goRouterProvider` is ready to receive navigation calls.
final fcmTapBridgeProvider = Provider<void>((ref) {
  final fcm = ref.read(fcmServiceProvider);
  final rideNavigationLatchTokens = <String, Object>{};
  final requestTapCoordinator = IncomingRequestTapCoordinator();

  Future<bool> waitForAuthenticatedCall(
    String callId,
    Map<String, dynamic> payload,
  ) async {
    final initialRemaining = _remainingCallTimeout(payload);
    if (initialRemaining <= Duration.zero) return false;
    final deadline = DateTime.now().add(initialRemaining);
    while (DateTime.now().isBefore(deadline)) {
      final authState = ref.read(authControllerProvider);
      if (authState is AuthAuthenticated) {
        return _remainingCallTimeout(payload) > Duration.zero &&
            !await _hasTerminalCallTombstone(callId);
      }
      if (authState is AuthUnauthenticated) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<bool> waitForAuthenticatedRequest(Map<String, dynamic> payload) async {
    final explicitDeadline = _requestDeadlineFromData(payload);
    final deadline = explicitDeadline ??
        DateTime.now().toUtc().add(const Duration(seconds: 20));
    while (DateTime.now().toUtc().isBefore(deadline)) {
      final authState = ref.read(authControllerProvider);
      if (authState is AuthAuthenticated) return true;
      if (authState is AuthUnauthenticated) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  void releaseRideRequestNavigationLatch(String rideId, Object token) {
    releaseRideRequestNavigationLatchIfOwned(
      latchTokens: rideNavigationLatchTokens,
      rideId: rideId,
      token: token,
      onRelease: () {
        ref
            .read(rideRequestNavigationInFlightProvider.notifier)
            .update((s) => {...s}..remove(rideId));
      },
    );
  }

  Object? claimRideRequestNavigation(String rideId) {
    if (rideRequestNavigationAlreadyActive(
      rideId: rideId,
      visibleRideId: ref.read(visibleRideRequestIdProvider),
      navigationInFlightRideIds: ref.read(
        rideRequestNavigationInFlightProvider,
      ),
    )) {
      return null;
    }
    final token = Object();
    rideNavigationLatchTokens[rideId] = token;
    ref
        .read(rideRequestNavigationInFlightProvider.notifier)
        .update((s) => {...s, rideId});
    return token;
  }

  void clearRideRequestInFlightFallback(VoidCallback releaseLatch) {
    // The loader releases this latch as soon as it either opens the
    // request screen, becomes unavailable, or is removed. This fallback is
    // only for a routing interruption before the loader can release it. It
    // is deliberately just beyond the loader's bounded 10-second hydrate,
    // not the full 30-second offer window.
    unawaited(
      Future<void>.delayed(rideRequestNavigationFallbackDuration, () {
        releaseLatch();
      }),
    );
  }

  Future<void> handleTapMessage(Map<String, dynamic> payload) async {
    final rawType = payload[NotificationPayload.keyType] as String?;
    // Backend emits dotted types ("job.request") in the FCM data payload.
    // The local-notification path normalises before re-encoding, but the
    // direct paths (onMessageOpenedApp + getInitialMessage) hand us the
    // raw `message.data` map — so we have to normalise here too, otherwise
    // every background / cold-start tap fell through to the default case.
    final type =
        rawType == null ? null : NotificationPayload.normaliseType(rawType);
    final actionId = payload[NotificationPayload.keyActionId]
        ?.toString()
        .trim()
        .toUpperCase();
    final router = ref.read(goRouterProvider);

    Future<void> openSystemTrayDestination(
      String destination, {
      Object? extra,
    }) =>
        openProviderTrayDestination(
          router,
          destination,
          extra: extra,
        );

    debugPrint('[FCM-tap] type=$type (raw=$rawType)');

    if (type != null && isEarningsSettlementNotification(type)) {
      // Background delivery cannot touch the main isolate's Riverpod cache.
      // Refresh it on tap before /earnings is routed.
      ref.read(refreshEarningsAfterSettlementProvider)();
    }

    final initialRideId = type == NotificationPayload.typeRideRequest
        ? (payload[NotificationPayload.keyRideId] ?? payload['ride_id'])
            ?.toString()
            .trim()
        : null;
    final preclaimedRideToken = initialRideId == null || initialRideId.isEmpty
        ? null
        : claimRideRequestNavigation(initialRideId);
    var rideClaimTransferredToLoader = false;

    void releaseUntransferredRideClaim() {
      if (rideClaimTransferredToLoader ||
          initialRideId == null ||
          initialRideId.isEmpty ||
          preclaimedRideToken == null) {
        return;
      }
      releaseRideRequestNavigationLatch(initialRideId, preclaimedRideToken);
    }

    // A malformed callback must not retain route ownership forever. Normal
    // exits release immediately below; this is only a last-resort exception
    // fence just beyond the server's 30-second decision window.
    if (preclaimedRideToken != null) {
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 35),
          releaseUntransferredRideClaim,
        ),
      );
    }

    final lifecycleRoute = providerLifecycleNotificationRoute(type ?? '');
    if (lifecycleRoute != null) {
      if (lifecycleRoute == '/account/documents') {
        ref.invalidate(verificationStatusProvider);
        // The destination fetches verification state immediately; refresh the
        // authenticated profile snapshot in parallel so other account surfaces
        // cannot keep showing an older pending/approved status after review.
        unawaited(
          ref.read(authControllerProvider.notifier).refreshProfile(),
        );
      }
      await openSystemTrayDestination(lifecycleRoute);
      releaseUntransferredRideClaim();
      return;
    }

    // Backend may send the job id under either `jobId` (camel) or
    // `job_id` (snake) depending on which emitter wrote the push.
    String? jobIdFromPayload() =>
        (payload[NotificationPayload.keyJobId] as String?) ??
        (payload['job_id'] as String?);

    DateTime? requestDeadlineFromPayload() => _requestDeadlineFromData(payload);

    // Shared landing path for every job-context tap that drops the user
    // on /active-job (bid accepted, supplement decisions, reminders,
    // welfare/stale check-ins). The slot is normally seeded when the
    // artisan taps "Accept & Start Job" on the bid-status banner; if
    // the trigger fired while the app was backgrounded/terminated, the
    // tap handler reaches this point with an empty slot and we have to
    // hydrate from GET /jobs/:id ourselves — otherwise the screen
    // renders its "No active job" empty state.
    Future<void> hydrateAndGoToActiveJob(String? jobId) async {
      final expectedSession = ref.read(currentAuthSessionIdentityProvider);
      if (expectedSession == null) {
        router.go('/home');
        return;
      }
      if (jobId == null) {
        debugPrint('[FCM-tap] active-job tap: no jobId in payload');
        await openSystemTrayDestination('/active-job');
        return;
      }
      final cached = ref.read(activeJobProvider).job;
      if (cached?.id == jobId) {
        // Slot already holds this job (foreground socket path or a
        // prior tap kept it warm) — straight to the screen.
        await openSystemTrayDestination('/active-job');
        return;
      }
      // Land on /home during the fetch so the user isn't staring at
      // _NoActiveJob for the duration of the round-trip — that's
      // exactly the regression we're avoiding.
      router.go('/home');
      try {
        final data = await ref.read(jobServiceProvider).getJob(jobId);
        if (!notificationHydrationSessionIsCurrent(
          expectedSession: expectedSession,
          currentSession: ref.read(currentAuthSessionIdentityProvider),
        )) {
          return;
        }
        final job = Job.fromJson(data);
        ref.read(activeJobProvider.notifier).setJob(job);
        // Preserve /home beneath this informational destination. A tray tap
        // has no meaningful prior Flutter route, so Back must not return to a
        // stale screen that happened to be visible before backgrounding.
        await openSystemTrayDestination('/active-job');
      } catch (e) {
        if (!notificationHydrationSessionIsCurrent(
          expectedSession: expectedSession,
          currentSession: ref.read(currentAuthSessionIdentityProvider),
        )) {
          return;
        }
        debugPrint('[FCM-tap] active-job hydrate failed for $jobId: $e');
        // Drop on My Jobs so the affected job is at least visible in
        // the list. Better than dumping the user on a blank screen.
        await openSystemTrayDestination('/trips');
      }
    }

    bool openRideRequestLoader(
      String rideId, {
      DateTime? deadline,
      String source = 'notification tap',
    }) {
      final offerId = payload[NotificationPayload.keyOfferId]?.toString();
      if (offerId != null && offerId.isNotEmpty) {
        ref
            .read(rideOfferIdByRideProvider.notifier)
            .update((offers) => {...offers, rideId: offerId});
      }
      if (deadline != null) {
        ref
            .read(rideRequestDeadlineByIdProvider.notifier)
            .update((m) => {...m, rideId: deadline});
      }
      final canUsePreclaim =
          rideId == initialRideId && preclaimedRideToken != null;
      if (canUsePreclaim && ref.read(visibleRideRequestIdProvider) == rideId) {
        debugPrint(
          '[FCM-tap] ride_request $rideId became visible while processing '
          'the notification — keeping current route',
        );
        return false;
      }
      final latchToken = canUsePreclaim
          ? preclaimedRideToken
          : claimRideRequestNavigation(rideId);
      if (latchToken == null) {
        debugPrint(
          '[FCM-tap] ride_request $rideId already visible or opening '
          '— keeping current route',
        );
        return false;
      }
      ref.read(surfacedRideIdsProvider.notifier).update((s) => {...s, rideId});
      final cachedRide = ref.read(incomingRideRequestProvider);
      final cachedActionableRide =
          cachedRide?.id == rideId && cachedRide?.status == RideStatus.requested
              ? cachedRide
              : null;
      if (cachedRide?.id == rideId) {
        ref.read(incomingRideRequestProvider.notifier).state = null;
      }
      void releaseLatch() =>
          releaseRideRequestNavigationLatch(rideId, latchToken);

      if (cachedActionableRide != null) {
        // The socket/recovery path delivered the full request while this tap
        // was awaiting its receipt. Its listener deliberately yielded to our
        // early route claim, so use that payload directly: mounting a loader
        // here would recreate the details → spinner → details flash.
        ref.read(visibleRideRequestOwnerProvider.notifier).state = null;
        ref.read(visibleRideRequestIdProvider.notifier).state = rideId;
        final currentPath = router.routerDelegate.currentConfiguration.uri.path;
        debugPrint(
          '[FCM-tap] opening cached ride_request $rideId from $source '
          '(currentPath=$currentPath)',
        );
        if (currentPath == '/ride-request') {
          unawaited(
            router.pushReplacement(
              rideRequestRouteLocation(rideId, expiresAt: deadline),
              extra: cachedActionableRide,
            ),
          );
        } else {
          unawaited(
            router.push(
              rideRequestRouteLocation(rideId, expiresAt: deadline),
              extra: cachedActionableRide,
            ),
          );
        }
        releaseLatch();
        return true;
      }

      clearRideRequestInFlightFallback(releaseLatch);
      if (canUsePreclaim) {
        rideClaimTransferredToLoader = true;
      }

      final currentPath = router.routerDelegate.currentConfiguration.uri.path;
      final routeExtra = RideRequestRouteExtra(
        rideId: rideId,
        navigationLatchToken: latchToken,
        releaseNavigationLatch: releaseLatch,
        // Passive copies from FlutterFire/local/native bridges are not user
        // retries. Keeping the replay claim through the offer window prevents
        // a late copy from reopening the same loader.
        allowNotificationRetry: () {},
        expiresAt: deadline,
      );
      debugPrint(
        '[FCM-tap] opening ride_request loader for $rideId from $source '
        '(currentPath=$currentPath)',
      );
      if (currentPath == '/ride-request') {
        unawaited(
          router.pushReplacement(
            rideRequestRouteLocation(rideId, expiresAt: deadline),
            extra: routeExtra,
          ),
        );
      } else {
        unawaited(
          router.push(
            rideRequestRouteLocation(rideId, expiresAt: deadline),
            extra: routeExtra,
          ),
        );
      }
      return true;
    }

    bool requestDeadlineExpired(DateTime deadline) {
      return !DateTime.now().toUtc().isBefore(deadline.toUtc());
    }

    Future<void> openJobRequest({required bool openBidSheet}) async {
      final jobId = jobIdFromPayload();
      if (jobId == null || jobId.isEmpty) {
        router.go('/home');
        return;
      }
      final deadline = requestDeadlineFromPayload();
      if (deadline != null && requestDeadlineExpired(deadline)) {
        await clearIncomingRequestAlert(
          type: NotificationPayload.typeJobRequest,
          requestId: jobId,
          offerId: payload[NotificationPayload.keyOfferId]?.toString(),
        );
        return;
      }
      ref.read(surfacedJobIdsProvider.notifier).update((s) => {...s, jobId});
      if (ref.read(incomingJobRequestProvider)?.id == jobId) {
        ref.read(incomingJobRequestProvider.notifier).state = null;
      }
      final stub = Job(
        id: jobId,
        status: JobStatus.open,
        categoryId: '',
        description: '',
        latitude: 0,
        longitude: 0,
        expiresAt: deadline?.toIso8601String(),
      );
      await openSystemTrayDestination(
        '/job-request',
        extra: JobRequestRouteExtra(
          job: stub,
          bidStatus: BidStatus.none,
          openBidSheet: openBidSheet,
        ),
      );
    }

    // A visible iOS receipt-protocol alert can be delivered while Dart is
    // suspended. Receipt it as soon as the provider taps the alert/action so
    // the backend starts the fresh 30-second decision window before any View,
    // Accept, or Skip path tries to hydrate or resolve the offer.
    if (type == NotificationPayload.typeRideRequest &&
        (int.tryParse(payload['offerVersion']?.toString() ?? '') ?? 0) >=
            rideOfferReceiptProtocolVersion) {
      if (!await waitForAuthenticatedRequest(payload)) {
        debugPrint('[FCM-tap] ride receipt auth unavailable');
        releaseUntransferredRideClaim();
        return;
      }
      final received = await acknowledgeRideOfferWithSocket(
        payload: payload,
        socket: ref.read(socketServiceProvider),
        rides: ref.read(rideServiceProvider),
      );
      if (received == null) {
        final rideId = payload[NotificationPayload.keyRideId]?.toString() ??
            payload['ride_id']?.toString();
        if (rideId != null && rideId.isNotEmpty) {
          await clearIncomingRequestAlert(
            type: NotificationPayload.typeRideRequest,
            requestId: rideId,
            offerId: payload[NotificationPayload.keyOfferId]?.toString(),
            reason: 'receipt_unavailable',
          );
        }
        router.go('/home');
        debugPrint('[FCM-tap] ride offer no longer receipt-capable');
        releaseUntransferredRideClaim();
        return;
      }
      payload.addAll(received.payload);
      ref
          .read(rideOfferIdByRideProvider.notifier)
          .update((offers) => {...offers, received.rideId: received.offerId});
      ref.read(rideRequestDeadlineByIdProvider.notifier).update(
            (deadlines) => {
              ...deadlines,
              received.rideId: received.decisionExpiresAt,
            },
          );
    }

    if (isActionableJobOfferPayload(type ?? '', payload) &&
        (int.tryParse(payload['offerVersion']?.toString() ?? '') ?? 0) >=
            jobOfferReceiptProtocolVersion) {
      if (!await waitForAuthenticatedRequest(payload)) {
        debugPrint('[FCM-tap] job receipt auth unavailable');
        releaseUntransferredRideClaim();
        return;
      }
      final expectedJobSession = ref.read(currentAuthSessionIdentityProvider);
      if (expectedJobSession == null) {
        releaseUntransferredRideClaim();
        return;
      }
      final received = await acknowledgeJobOffer(
        payload: payload,
        jobs: ref.read(jobServiceProvider),
      );
      if (received == null || !received.hasExactReceipt) {
        final jobId = payload[NotificationPayload.keyJobId]?.toString() ??
            payload['job_id']?.toString();
        if (jobId != null && jobId.isNotEmpty) {
          await clearIncomingRequestAlert(
            type: NotificationPayload.typeJobRequest,
            requestId: jobId,
            offerId: payload[NotificationPayload.keyOfferId]?.toString(),
            reason: 'receipt_unavailable',
          );
        }
        router.go('/home');
        debugPrint('[FCM-tap] job offer no longer receipt-capable');
        releaseUntransferredRideClaim();
        return;
      }
      if (ref.read(currentAuthSessionIdentityProvider) != expectedJobSession) {
        releaseUntransferredRideClaim();
        return;
      }
      payload.addAll(received.payload);
      ref.read(jobOfferIdByJobProvider.notifier).update(
            (offers) => {...offers, received.jobId: received.offerId!},
          );
      ref.read(lastJobOfferIdByJobProvider.notifier).update(
            (offers) => {...offers, received.jobId: received.offerId!},
          );
      final deadline = received.decisionExpiresAt;
      if (deadline != null) {
        ref.read(jobOfferDeadlineByJobProvider.notifier).update(
              (deadlines) => {...deadlines, received.jobId: deadline},
            );
      }
      ref.read(jobOfferDismissalProvider.notifier).state = null;
      // The user's tray action owns this exact offer before any subsequent
      // hydration await. Socket/FCM copies must enrich this path, not stack a
      // second modal over the destination being opened.
      ref
          .read(surfacedJobIdsProvider.notifier)
          .update((ids) => {...ids, received.jobId});
      if (ref.read(incomingJobRequestProvider)?.id == received.jobId) {
        ref.read(incomingJobRequestProvider.notifier).state = null;
      }
    }

    // Local-notification and native overlay actions all converge here. The
    // native bridges persist the action first, so this may run during a cold
    // start after authentication is restored.
    if (actionId != null && actionId.isNotEmpty) {
      final deadline = requestDeadlineFromPayload();
      if (deadline != null && requestDeadlineExpired(deadline)) {
        final requestId = type == NotificationPayload.typeRideRequest
            ? payload[NotificationPayload.keyRideId]?.toString()
            : payload[NotificationPayload.keyJobId]?.toString();
        if (type != null && requestId != null && requestId.isNotEmpty) {
          await clearIncomingRequestAlert(
            type: type,
            requestId: requestId,
            offerId: payload[NotificationPayload.keyOfferId]?.toString(),
          );
        }
        debugPrint('[Request-action] ignored expired action=$actionId');
        releaseUntransferredRideClaim();
        return;
      }
      if (!await waitForAuthenticatedRequest(payload)) {
        debugPrint('[Request-action] auth unavailable for action=$actionId');
        releaseUntransferredRideClaim();
        return;
      }

      switch (actionId) {
        case NotificationPayload.actionRideAccept:
          final rideId = payload[NotificationPayload.keyRideId]?.toString();
          if (rideId == null || rideId.isEmpty) {
            releaseUntransferredRideClaim();
            return;
          }
          final accepted = await ref
              .read(activeRideProvider.notifier)
              .acceptRideFromNotification(
                rideId,
                offerId: payload[NotificationPayload.keyOfferId]?.toString(),
              );
          if (accepted) {
            await clearIncomingRequestAlert(
              type: NotificationPayload.typeRideRequest,
              requestId: rideId,
              offerId: payload[NotificationPayload.keyOfferId]?.toString(),
            );
            // restore() publishes activeRide before this Future completes.
            // The shell listener may therefore already own navigation. A
            // second go() to the same route rebuilds the time-bound screen.
            final currentPath =
                router.routerDelegate.currentConfiguration.uri.path;
            if (shouldNavigateToActiveRideFromNotification(currentPath)) {
              router.go('/active-ride');
            }
          } else {
            openRideRequestLoader(
              rideId,
              deadline: deadline,
              source: 'failed native accept',
            );
          }
          releaseUntransferredRideClaim();
          return;
        case NotificationPayload.actionRideSkip:
          final rideId = payload[NotificationPayload.keyRideId]?.toString();
          if (rideId == null || rideId.isEmpty) {
            releaseUntransferredRideClaim();
            return;
          }
          final skipped = await ref
              .read(activeRideProvider.notifier)
              .declineRideFromNotification(
                rideId,
                offerId: payload[NotificationPayload.keyOfferId]?.toString(),
              );
          if (skipped) {
            await clearIncomingRequestAlert(
              type: NotificationPayload.typeRideRequest,
              requestId: rideId,
              offerId: payload[NotificationPayload.keyOfferId]?.toString(),
            );
            ref.read(incomingRideRequestProvider.notifier).state = null;
            router.go('/home');
          } else {
            openRideRequestLoader(
              rideId,
              deadline: deadline,
              source: 'failed native skip',
            );
          }
          releaseUntransferredRideClaim();
          return;
        case NotificationPayload.actionJobSkip:
          final jobId = jobIdFromPayload();
          if (jobId == null || jobId.isEmpty) {
            releaseUntransferredRideClaim();
            return;
          }
          try {
            final actionOfferId =
                payload[NotificationPayload.keyOfferId]?.toString();
            await ref.read(jobServiceProvider).declineJobRequest(
                  jobId,
                  offerId: actionOfferId,
                  reason: 'notification_skip',
                );
            await clearStoredJobOffer(actionOfferId);
            final currentOfferId = ref.read(jobOfferIdByJobProvider)[jobId];
            final stillOwnsOffer = jobOfferActionStillOwnsCurrent(
              capturedOfferId: actionOfferId,
              currentOfferId: currentOfferId,
              lastExactOfferId: ref.read(lastJobOfferIdByJobProvider)[jobId],
            );
            if (!stillOwnsOffer &&
                (actionOfferId == null || actionOfferId.isEmpty)) {
              return;
            }
            if (stillOwnsOffer) {
              ref.read(jobOfferIdByJobProvider.notifier).update((offers) {
                if (actionOfferId != null && offers[jobId] != actionOfferId) {
                  return offers;
                }
                return {...offers}..remove(jobId);
              });
              ref
                  .read(jobOfferDeadlineByJobProvider.notifier)
                  .update((deadlines) => {...deadlines}..remove(jobId));
              ref.read(pendingIncomingJobsProvider.notifier).remove(jobId);
            }
            await clearIncomingRequestAlert(
              type: NotificationPayload.typeJobRequest,
              requestId: jobId,
              offerId: actionOfferId,
            );
            if (stillOwnsOffer) router.go('/home');
          } catch (error) {
            debugPrint('[Request-action] job skip failed: $error');
            // The action notification is already gone. Hand off to the full
            // request screen so the artisan can retry instead of silently
            // losing the still-live offer on a transient network failure.
            await openJobRequest(openBidSheet: false);
          }
          releaseUntransferredRideClaim();
          return;
        case NotificationPayload.actionJobSubmitBid:
          await openJobRequest(openBidSheet: true);
          releaseUntransferredRideClaim();
          return;
        case NotificationPayload.actionRideView:
        case NotificationPayload.actionJobView:
          // Continue into the normal type-based view routing below.
          break;
      }
    }

    if (requestTapCoordinator.shouldAbortViewAfterDecision(payload)) {
      debugPrint(
        '[RequestTap] decision already owns this request — '
        'skipping trailing view navigation',
      );
      releaseUntransferredRideClaim();
      return;
    }

    switch (type) {
      case NotificationPayload.typeAnnouncement:
        await openSystemTrayDestination(
          providerAnnouncementRoute(
            payload[NotificationPayload.keyDestination],
          ),
        );
        break;

      case NotificationPayload.typeCallIncoming:
        final callId = payload['callId'] as String?;
        if (callId == null || callId.isEmpty) {
          debugPrint(
            '[FCM-tap] call_incoming missing callId; '
            'keys=${payload.keys.toList()}',
          );
          router.go('/home');
          break;
        }
        if (!await waitForAuthenticatedCall(callId, payload)) {
          await LocalNotificationService.instance.cancelIncomingCall(callId);
          debugPrint(
            '[FCM-tap] call no longer open or auth was not restored: $callId',
          );
          break;
        }
        if (Platform.isAndroid) {
          await LocalNotificationService.instance.cancelIncomingCall(callId);
        }
        // A notification tap only opens the explicit Accept/Decline screen.
        // CallKit's Answer action is the sole native auto-accept path.
        router.go('/calls/$callId');
        break;

      case NotificationPayload.typeJobRequest:
        // Backend may send the job id under either `jobId` (camel) or
        // `job_id` (snake) depending on which emitter wrote the push;
        // accept both so a casing drift doesn't silently route to /home.
        final jobId = (payload[NotificationPayload.keyJobId] as String?) ??
            (payload['job_id'] as String?);
        debugPrint(
          '[FCM-tap] job_request jobId=$jobId '
          'keys=${payload.keys.toList()}',
        );
        if (jobId == null) {
          router.go('/home');
          debugPrint('[FCM-tap] no jobId in payload — running recovery');
          await recoverPendingRequestsNow(ref);
          break;
        }
        // Suppress the foreground modal for this job — the user already
        // acknowledged the notification by tapping it, so stacking the
        // in-app sheet on top of the bid-details screen is redundant.
        // The socket/poller's dedup reads [surfacedJobIdsProvider]; the
        // listener's post-frame recovery reads [incomingJobRequestProvider].
        // Clearing both kills every path that could pop a modal on top.
        ref.read(surfacedJobIdsProvider.notifier).update((s) => {...s, jobId});
        if (ref.read(incomingJobRequestProvider)?.id == jobId) {
          ref.read(incomingJobRequestProvider.notifier).state = null;
        }
        // Details for this job are already on screen (opened in-app via the
        // modal/socket path before the user backgrounded) — keep it. Without
        // this guard the tap tears the screen down and re-pushes a stub that
        // re-fetches the same job, which the artisan experiences as
        // details → loading → details.
        if (ref.read(visibleJobRequestIdProvider) == jobId) {
          debugPrint('[FCM-tap] job_request $jobId already visible — keeping');
          break;
        }
        // Land on /home so dismissing /job-request returns to a sane
        // shell, then push the bid details synchronously with a stub
        // Job carrying only the id. JobRequestScreen.initState() calls
        // _hydrateJob() which fetches the full record from
        // GET /jobs/:id and rerenders — so the screen does the network
        // I/O itself, against its own loading lifecycle, instead of us
        // holding the FCM callback open while a Render cold-start
        // refresh runs to 60 seconds and the user sees nothing happen.
        debugPrint('[FCM-tap] pushing /job-request stub for $jobId');
        await openJobRequest(openBidSheet: false);
        break;

      case NotificationPayload.typeRideRequest:
        // Backend may send the ride id under `rideId` (camel) or `ride_id`
        // (snake) depending on which emitter wrote the push.
        final rideId = (payload[NotificationPayload.keyRideId] as String?) ??
            (payload['ride_id'] as String?);
        debugPrint(
          '[FCM-tap] ride_request rideId=$rideId '
          'keys=${payload.keys.toList()}',
        );
        if (rideId == null) {
          router.go('/home');
          debugPrint('[FCM-tap] no rideId in payload — running recovery');
          await recoverPendingRequestsNow(ref);
          break;
        }
        final deadline = requestDeadlineFromPayload();
        if (deadline != null) {
          ref
              .read(rideRequestDeadlineByIdProvider.notifier)
              .update((m) => {...m, rideId: deadline});
          if (requestDeadlineExpired(deadline)) {
            debugPrint('[FCM-tap] ride_request $rideId expired before tap');
            await clearIncomingRequestAlert(
              type: NotificationPayload.typeRideRequest,
              requestId: rideId,
              offerId: payload[NotificationPayload.keyOfferId]?.toString(),
            );
            router.go('/home');
            break;
          }
        }
        if (ref.read(visibleRideRequestIdProvider) == rideId) {
          debugPrint('[FCM-tap] ride_request $rideId already visible');
          break;
        }
        openRideRequestLoader(
          rideId,
          deadline: deadline,
          source: 'ride_request notification',
        );
        break;

      case NotificationPayload.typeBidAccepted:
      case NotificationPayload.typeSupplementApproved:
      case NotificationPayload.typeSupplementRejected:
        await hydrateAndGoToActiveJob(jobIdFromPayload());
        break;

      case NotificationPayload.typeRideSettled:
      case NotificationPayload.typePaymentReceived:
      case NotificationPayload.typeEarningsUpdated:
      case NotificationPayload.typeJobPaymentReleasing:
      // Client confirmed the work and the payout has been released —
      // earnings is where the artisan wants to land.
      case NotificationPayload.typeJobConfirmedComplete:
        await openSystemTrayDestination('/earnings');
        break;

      // Cancellations (client- or platform-initiated) — drop the user
      // on My Jobs / My Trips so they see the cancelled booking in
      // their list with the cancelled status, instead of a generic
      // home tab that gives no context.
      case NotificationPayload.typeJobCancelled:
      case NotificationPayload.typeJobCancelledByClient:
        await openSystemTrayDestination('/trips');
        break;

      case NotificationPayload.typeRideCancelled:
        final rideId =
            (payload[NotificationPayload.keyRideId] ?? payload['ride_id'])
                ?.toString();
        final currentRide = ref.read(activeRideProvider).ride;
        if (currentRide != null && currentRide.id != rideId) {
          debugPrint(
            '[FCM-tap] ignoring delayed cancellation for $rideId while '
            '${currentRide.id} is active',
          );
          break;
        }
        final cleared =
            ref.read(activeRideProvider.notifier).clearRideIfMatches(rideId);
        await openSystemTrayDestination(cleared ? '/home' : '/trips');
        break;

      // Reminders, staleness pings and welfare checks all relate to the
      // active job — drop the artisan straight onto the active-job
      // screen so they can advance the timeline or send an update.
      // Same hydration path as bid-accepted: without it the screen
      // would render _NoActiveJob whenever the slot wasn't pre-warmed
      // by the foreground socket flow.
      case NotificationPayload.typeJobReminder24h:
      case NotificationPayload.typeJobReminder2h:
      case NotificationPayload.typeJobCheckin8h:
      case NotificationPayload.typeJobStale24h:
      case NotificationPayload.typeJobStale48h:
      case NotificationPayload.typeJobWelfareCheck:
        await hydrateAndGoToActiveJob(jobIdFromPayload());
        break;

      // Admin opened a job up because no bids landed in time, or assigned
      // this artisan for a quote. Fetch the job first so the screen can render
      // context; bounce to /home on failure.
      case NotificationPayload.typeJobNoBidsEscalated:
        final jobId = payload[NotificationPayload.keyJobId] as String?;
        if (jobId == null) {
          router.go('/home');
          break;
        }
        try {
          final data = await ref.read(jobServiceProvider).getJob(jobId);
          final job = Job.fromJson(data);
          await openSystemTrayDestination('/job-request', extra: job);
        } catch (e) {
          debugPrint('[FCM] tap fetch failed for job $jobId: $e');
          router.go('/home');
        }
        break;

      case NotificationPayload.typeJobManuallyAssigned:
        final mode = (payload['mode'] ?? payload['assignmentMode'])
            ?.toString()
            .trim()
            .toLowerCase();
        if (mode == 'confirm') {
          await hydrateAndGoToActiveJob(jobIdFromPayload());
          break;
        }
        final jobId = jobIdFromPayload();
        if (jobId == null) {
          router.go('/home');
          break;
        }
        final expectedSession = ref.read(currentAuthSessionIdentityProvider);
        if (expectedSession == null) {
          router.go('/home');
          break;
        }
        try {
          final data = await ref.read(jobServiceProvider).getJob(jobId);
          if (ref.read(currentAuthSessionIdentityProvider) != expectedSession) {
            break;
          }
          final job = Job.fromJson(data);
          await openSystemTrayDestination('/job-request', extra: job);
        } catch (e) {
          debugPrint('[FCM] tap fetch failed for job $jobId: $e');
          router.go('/home');
        }
        break;

      case NotificationPayload.typeNewMessage:
        // Push directly into the chat screen for the booking the message
        // belongs to. Falls back to /messages when the payload is
        // missing the booking ids — that route already lists the active
        // chats.
        final rawBookingType =
            payload[NotificationPayload.keyBookingType] as String?;
        final bookingType = ChatBookingType.fromWire(rawBookingType);
        final rideId = payload[NotificationPayload.keyRideId] as String?;
        final jobId = payload[NotificationPayload.keyJobId] as String?;
        final bookingId =
            (payload[NotificationPayload.keyBookingId] as String?) ??
                (bookingType == ChatBookingType.ride ? rideId : jobId);
        if (bookingType == null || bookingId == null || bookingId.isEmpty) {
          await openSystemTrayDestination('/messages');
          break;
        }
        // Hydrate the peer (client) details from the booking so the chat
        // screen header renders the same way it does when opened from
        // the active-ride / active-job surfaces. The FCM payload only
        // carries the notification title (usually "New message"), which
        // would otherwise blank out the peer card.
        String peerName = 'Chat';
        String peerStatus = '';
        String? jobTitle;
        try {
          if (bookingType == ChatBookingType.ride) {
            final raw = await ref.read(rideServiceProvider).getRide(bookingId);
            final ride = Ride.fromJson(raw);
            final name = ride.clientName?.trim();
            if (name != null && name.isNotEmpty) peerName = name;
            peerStatus = _ridePeerStatusFor(ride.status.toJson());
          } else {
            final raw = await ref.read(jobServiceProvider).getJob(bookingId);
            final job = Job.fromJson(raw);
            final name = job.clientName?.trim();
            if (name != null && name.isNotEmpty) peerName = name;
            jobTitle = job.categoryName;
            peerStatus = _jobPeerStatusFor(job.status.toJson());
          }
        } catch (e) {
          debugPrint('[FCM] hydrate booking for chat failed: $e');
        }
        await openSystemTrayDestination(
          '/chat',
          extra: <String, Object?>{
            'bookingType': bookingType,
            'bookingId': bookingId,
            'peerName': peerName,
            'peerStatus': peerStatus,
            if (jobTitle != null) 'jobTitle': jobTitle,
          },
        );
        break;

      // Backend asks the provider to rate the counter-party for a
      // completed booking. There's no dedicated rating screen in this
      // app — the rating UI lives as a modal sheet — so we land on
      // /home and surface the matching sheet over it. Hydrate the
      // counter-party's first name so the title reads "Rate Akua"
      // rather than the generic "Rate your client" fallback.
      case NotificationPayload.typeRatingPrompt:
        final bookingType =
            payload[NotificationPayload.keyBookingType] as String?;
        final bookingId =
            (payload[NotificationPayload.keyBookingId] as String?) ??
                (bookingType == 'ride'
                    ? payload[NotificationPayload.keyRideId] as String?
                    : payload[NotificationPayload.keyJobId] as String?);
        if (bookingId == null || bookingId.isEmpty) {
          router.go('/home');
          break;
        }
        router.go('/home');
        // Defer past the route push so the navigator key resolves to the
        // newly-mounted shell rather than a popping route.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final ctx = router.routerDelegate.navigatorKey.currentContext;
        if (ctx == null) break;
        if (bookingType == 'ride') {
          var firstName = 'Passenger';
          try {
            final raw = await ref.read(rideServiceProvider).getRide(bookingId);
            final ride = Ride.fromJson(raw);
            final name = ride.clientName;
            if (name != null && name.trim().isNotEmpty) {
              firstName = name.trim().split(RegExp(r'\s+')).first;
            }
          } catch (e) {
            debugPrint('[FCM] hydrate ride for rating failed: $e');
          }
          if (!ctx.mounted) break;
          await showRatePassengerSheet(
            ctx,
            rideId: bookingId,
            passengerFirstName: firstName,
          );
        } else if (bookingType == 'artisan_job' || bookingType == 'job') {
          var firstName = 'Client';
          try {
            final raw = await ref.read(jobServiceProvider).getJob(bookingId);
            final job = Job.fromJson(raw);
            final name = job.clientName;
            if (name != null && name.trim().isNotEmpty) {
              firstName = name.trim().split(RegExp(r'\s+')).first;
            }
          } catch (e) {
            debugPrint('[FCM] hydrate job for rating failed: $e');
          }
          if (!ctx.mounted) break;
          await showRateClientSheet(
            ctx,
            jobId: bookingId,
            clientFirstName: firstName,
          );
          // After the artisan rates the client, drop them on /earnings
          // — payout is released, the job is done, and there's nothing
          // left to do on /home. Mirrors the post-rating navigation in
          // active_job_screen.
          if (ctx.mounted) {
            router.go('/earnings');
          }
        }
        break;

      // ── Support tickets ───────────────────────────────────────────────
      case NotificationPayload.typeSupportTicketMessage:
      case NotificationPayload.typeSupportTicketStatusChanged:
        final ticketId = payload[NotificationPayload.keyTicketId] as String?;
        if (ticketId != null && ticketId.isNotEmpty) {
          await openSystemTrayDestination(
            '/account/support/tickets/$ticketId',
          );
        } else {
          await openSystemTrayDestination('/account/support/tickets');
        }
        break;

      case NotificationPayload.typeProviderResponseBlockWarning:
        await openSystemTrayDestination('/home');
        break;

      case NotificationPayload.typeProviderResponseBlockStarted:
        await openSystemTrayDestination('/account/support');
        break;

      case NotificationPayload.typeBidRejected:
      default:
        router.go('/home');
    }
    releaseUntransferredRideClaim();
  }

  fcm.onTapMessage = (payload) {
    return requestTapCoordinator.dispatch(
      payload,
      () => handleTapMessage(payload),
    );
  };

  final nativeActionBridge = IncomingRequestActionBridge(
    handleAction: (payload) async {
      final handler = fcm.onTapMessage;
      if (handler != null) await handler(payload);
    },
  );
  unawaited(nativeActionBridge.start());
  ref.listen<AuthState>(authControllerProvider, (previous, next) {
    if (previous is! AuthAuthenticated) return;
    final sameProvider = next is AuthAuthenticated &&
        previous.user.id == next.user.id &&
        previous.user.role == next.user.role;
    if (!sameProvider) {
      requestTapCoordinator.reset();
      rideNavigationLatchTokens.clear();
    }
  });
  ref.onDispose(() {
    requestTapCoordinator.dispose();
    unawaited(nativeActionBridge.dispose());
  });
});

/// Renders a friendly "what is the client up to right now" string for the
/// chat header. Mirrors the labels the active-ride screen passes when it
/// opens the chat, so a notification-tap and an in-app tap land on the
/// same UI.
String _ridePeerStatusFor(String? rideStatus) {
  switch (rideStatus) {
    case 'accepted':
    case 'driver_en_route':
      return 'Waiting for pickup';
    case 'arrived':
      return 'At the pickup point';
    case 'in_progress':
      return 'On the trip';
    case 'completed':
      return 'Trip completed';
    case 'cancelled':
      return 'Trip cancelled';
    default:
      return '';
  }
}

String _jobPeerStatusFor(String? jobStatus) {
  switch (jobStatus) {
    case 'pending':
    case 'open':
    case 'bidding':
      return 'Reviewing bids';
    case 'awarded':
    case 'accepted':
    case 'en_route':
    case 'driver_en_route':
      return 'Awaiting arrival';
    case 'arrived':
      return 'On site';
    case 'in_progress':
      return 'Job in progress';
    case 'artisan_marked_complete':
      return 'Awaiting client confirmation';
    case 'completed':
      return 'Job completed';
    case 'cancelled':
      return 'Job cancelled';
    default:
      return '';
  }
}
