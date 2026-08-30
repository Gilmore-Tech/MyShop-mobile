import 'dart:async';
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart'
    show AppCallSession, AuthSessionIdentity;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart' show ChatBookingType;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../app/router.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/ride/providers/ride_provider.dart'
    show rideReceiptProvider;
import '../../features/ride/widgets/rate_ride_sheet.dart';
import '../../features/services/widgets/rate_job_sheet.dart';
import '../di/providers.dart';
import 'local_notification_service.dart';

const _defaultIncomingCallTimeout = Duration(seconds: 60);
const _terminalCallTombstoneFallback = Duration(minutes: 2);
const _terminalCallTombstonePrefix = 'myshop.call_terminal.';

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

/// Background isolate entry-point — FCM spawns a short-lived isolate to
/// call this when a push arrives while the app is terminated or in the
/// background. MUST be a top-level function tagged with
/// `@pragma('vm:entry-point')` or the AOT tree-shaker will drop it.
///
/// We re-initialise the local notification plugin here because isolate
/// state is NOT shared with the main isolate.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    '[FCM-bg] message arrived: '
    'type=${message.data[NotificationPayload.keyType]} '
    'hasNotificationField=${message.notification != null} '
    'keys=${message.data.keys.toList()}',
  );

  if (await _handleCallEndedFromRemote(message, source: 'background-fcm')) {
    return;
  }
  if (await _showIncomingCallFromRemote(message, source: 'background-fcm')) {
    return;
  }

  // Backend now sends a top-level `notification` field on every push so
  // FCM auto-displays the system tray banner in background/terminated.
  // Rendering our local notification on top of that produces 2× banners
  // (one from FCM SDK, one from flutter_local_notifications) — bail when
  // FCM has already drawn it. Only render manually for true data-only
  // pushes (no `notification` field present).
  if (message.notification != null) return;
  await LocalNotificationService.instance.init();
  await _renderFromRemote(message);
}

Future<bool> _showIncomingCallFromRemote(
  RemoteMessage message, {
  required String source,
}) async {
  final type = _remoteType(message);
  if (type != NotificationPayload.typeCallIncoming) return false;

  final callId = message.data[NotificationPayload.keyCallId]?.toString();
  if (callId == null || callId.isEmpty) {
    debugPrint('[FCM] $source call_incoming missing required call identifier');
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
    debugPrint('[FCM] $source call_ended missing required call identifier');
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

String get _platformName {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'unknown';
}

Future<void> _renderFromRemote(
  RemoteMessage message, {
  Duration? callTimeout,
}) async {
  final data = message.data;
  final type = _remoteType(message);
  if (type == null) return;

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
      debugPrint('[FCM] call_incoming missing required call identifier');
      return;
    }
    timeoutAfter = callTimeout ?? _remainingCallTimeout(data);
    if (timeoutAfter <= Duration.zero) {
      await LocalNotificationService.instance.cancelIncomingCall(callId);
      debugPrint('[FCM] ignored stale call_incoming: $callId');
      return;
    }
  }

  final title = message.notification?.title ?? data['title']?.toString() ?? '';
  final body = message.notification?.body ?? data['body']?.toString() ?? '';

  // Pass through every non-title/body data key so the tap handler can
  // read jobId / rideId / bidId / chatId / notificationId.
  final extras = <String, String>{};
  for (final entry in data.entries) {
    if (entry.key == NotificationPayload.keyType) continue;
    if (entry.key == 'title' || entry.key == 'body') continue;
    final v = entry.value;
    if (v is String && v.isNotEmpty) extras[entry.key] = v;
  }

  await LocalNotificationService.instance.showTimelineUpdate(
    type: type,
    title: title.isEmpty ? _fallbackTitle(type) : title,
    body: body.isEmpty ? _fallbackBody(type) : body,
    extras: extras,
    timeoutAfter: timeoutAfter,
  );
}

String _fallbackTitle(String type) {
  switch (type) {
    case NotificationPayload.typeRideDriverAssigned:
      return 'Driver assigned';
    case NotificationPayload.typeRideDriverEnRoute:
      return 'Driver is on the way';
    case NotificationPayload.typeRideDriverArrived:
      return 'Your driver has arrived';
    case NotificationPayload.typeRideInProgress:
      return 'Ride started';
    case NotificationPayload.typeRideCompleted:
      return 'Ride complete';
    case NotificationPayload.typeRideCancelled:
      return 'Ride cancelled';
    case NotificationPayload.typeJobBidSubmitted:
      return 'New bid on your job';
    case NotificationPayload.typeJobArtisanEnRoute:
      return 'Artisan is on the way';
    case NotificationPayload.typeJobArtisanArrived:
      return 'Your artisan has arrived';
    case NotificationPayload.typeJobInProgress:
      return 'Job started';
    case NotificationPayload.typeJobMarkedComplete:
      return 'Artisan marked job complete';
    case NotificationPayload.typeJobConfirmCompletionRequested:
      return 'Confirm job completion';
    case NotificationPayload.typeJobCompleted:
      return 'Job complete';
    case NotificationPayload.typeJobCancelled:
    case NotificationPayload.typeJobCancelledByArtisan:
      return 'Job cancelled';
    case NotificationPayload.typeJobForceCompleted:
      return 'Job auto-completed';
    case NotificationPayload.typeJobNoBidsEscalated:
      return 'Looking for an artisan';
    case NotificationPayload.typeJobArtisanNoShow:
      return 'Artisan didn\'t show up';
    case NotificationPayload.typeJobCheckin8h:
      return 'How is the job going?';
    case NotificationPayload.typeJobStale24h:
      return 'Job needs an update';
    case NotificationPayload.typeJobStale48h:
      return 'Job will auto-cancel soon';
    case NotificationPayload.typeJobReminder2h:
      return 'Job starts in 2 hours';
    case NotificationPayload.typeJobSupplementRequested:
      return 'Supplement request';
    case NotificationPayload.typeNewMessage:
      return 'New message';
    case NotificationPayload.typePaymentConfirmed:
      return 'Payment received';
    case NotificationPayload.typeRatingPrompt:
      return 'Rate your experience';
    case NotificationPayload.typeSupportTicketMessage:
      return 'New reply from support';
    case NotificationPayload.typeSupportTicketStatusChanged:
      return 'Ticket update';
    default:
      return 'MyShop';
  }
}

String _fallbackBody(String type) {
  switch (type) {
    case NotificationPayload.typeRideDriverArrived:
      return 'Your driver is waiting at the pickup point.';
    case NotificationPayload.typeJobArtisanArrived:
      return 'Your artisan is at the location.';
    case NotificationPayload.typeJobMarkedComplete:
    case NotificationPayload.typeJobConfirmCompletionRequested:
      return 'Confirm the work to release payment.';
    case NotificationPayload.typeJobBidSubmitted:
      return 'An artisan has placed a bid on your request.';
    case NotificationPayload.typeJobNoBidsEscalated:
      return 'No bids yet — our team is finding an artisan for you.';
    case NotificationPayload.typeJobArtisanNoShow:
      return 'The artisan didn\'t arrive. Tap to rebook or get help.';
    case NotificationPayload.typeJobReminder2h:
      return 'Your scheduled job starts in two hours.';
    case NotificationPayload.typeJobCheckin8h:
      return 'Tap to leave a quick update on the job.';
    case NotificationPayload.typeJobStale24h:
      return 'No updates in 24 hours. Tap to nudge the artisan.';
    case NotificationPayload.typeJobStale48h:
      return 'The job will auto-cancel if there\'s no progress.';
    case NotificationPayload.typeJobForceCompleted:
      return 'We auto-completed this job. Tap to review or dispute.';
    case NotificationPayload.typeRatingPrompt:
      return 'Tap to leave a rating before the 24-hour window closes.';
    case NotificationPayload.typeSupportTicketMessage:
      return 'Tap to read and reply.';
    case NotificationPayload.typeSupportTicketStatusChanged:
      return 'Tap to see the latest status.';
    default:
      return 'Open MyShop to see the latest update.';
  }
}

/// Coordinates the Firebase Messaging lifecycle for the client app.
///
///   1. [init] — wire handlers (background + foreground + tap) once at
///      app start.
///   2. [syncToken] — call after the user authenticates so the backend
///      knows where to route pushes. Re-fires on token refresh.
///
/// [onTapMessage] is invoked when the user taps a system-tray notification
/// (our own via [LocalNotificationService] or one raw from FCM). Payload
/// keys: `{ type, jobId | rideId | bidId | chatId }`.
class FcmService {
  FcmService(this._ref);

  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<RemoteMessage>? _openedMessageSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<VoipCallBridgeEvent>? _voipEventSub;
  StreamSubscription<AppCallSession>? _incomingCallStateSub;
  final Set<String> _trackedIncomingCallIds = <String>{};
  AuthSessionIdentity? _deviceRegistrationIdentity;
  AuthSessionIdentity? _voipRegistrationIdentity;
  int _lifecycleEpoch = 0;
  bool _initialised = false;
  Future<void>? _initializing;

  void Function(Map<String, dynamic> payload)? onTapMessage;

  Future<void> init() {
    debugPrint('[FCM] init() called (initialised=$_initialised)');
    if (_initialised) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    // Must be registered before any message can arrive.
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    debugPrint('[FCM] background handler registered');

    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    LocalNotificationService.instance.onTap = (payload) {
      _markNotificationRead(payload);
      onTapMessage?.call(payload);
    };

    // Foreground message — surface a local notification even when the
    // user is inside the app so they can't miss an urgent arrival while
    // viewing an unrelated screen.
    //
    // `new_message` is the exception: the chat socket already delivers
    // the message and the in-app surfaces (active-ride/job header, the
    // chat screen, the unread badge on the entry-point button) reflect
    // it. Suppress the OS banner so we don't double-notify.
    _foregroundMessageSub ??= FirebaseMessaging.onMessage.listen((
      message,
    ) async {
      debugPrint('[FCM] foreground message received');
      if (await _handleCallEndedFromRemote(
        message,
        source: 'foreground-fcm',
      )) {
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

      // FCM does NOT auto-display in foreground (Android & iOS) — the SDK
      // hands it to onMessage and lets the app decide. So we always render
      // here, irrespective of whether `notification` is present, to give
      // the user a heads-up while they're in another tab. The background
      // handler does the opposite (skips if `notification` is present) to
      // avoid double-rendering with FCM's auto-display.
      //
      // Previously we suppressed `new_message` in foreground because the
      // open chat screen already surfaces the message via the chat socket.
      // That made notifications silently disappear when the user was on
      // any *other* in-app screen, and there was no global feedback that
      // a new message had arrived. We now render every time and rely on
      // the de-dupe id (per booking) to replace older banners rather than
      // stack them.
      await _renderFromRemote(message);
    });

    // Tap on push while app was backgrounded → resumed.
    _openedMessageSub ??= FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      debugPrint('[FCM] app opened from a background notification');
      final payload = Map<String, dynamic>.from(message.data);
      _markNotificationRead(payload);
      onTapMessage?.call(payload);
    });

    // Cold-start: app was terminated, launched by a push tap.
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] initial notification received');
      final payload = Map<String, dynamic>.from(initialMessage.data);
      _markNotificationRead(payload);
      // Defer so the router is mounted before we try to navigate.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        onTapMessage?.call(payload);
      });
    }

    // Defense in depth: the auth bridge fires syncToken when state hits
    // AuthAuthenticated, but on cold start that can fire BEFORE init()
    // has requested permission — getToken() then returns null and the
    // single-shot bridge never re-fires. Kick it again now that perms
    // are granted; syncToken is idempotent (registerDevice is an upsert).
    final authState = _ref.read(clientAuthControllerProvider);
    if (authState is AuthAuthenticated) {
      unawaited(syncToken());
    }
    _initialised = true;
    debugPrint('[FCM] initialisation complete');
  }

  /// Fires a best-effort `PATCH /notifications/:id/read` when the push
  /// carries a `notificationId`. Clears the in-app bell in the background
  /// so a tap also settles the inbox. Swallows errors — the user has
  /// already acted, we just didn't get to record it.
  void _markNotificationRead(Map<String, dynamic> payload) {
    final id = payload[NotificationPayload.keyNotificationId] as String?;
    if (id == null || id.isEmpty) return;
    _ref
        .read(notificationServiceProvider)
        .markAsRead(id)
        .catchError((Object e) {
      debugPrint('[FCM] markAsRead($id) failed: $e');
    });
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
    }

    // iOS: FCM derives its token from the APNs device token. On cold
    // start `getToken()` throws `apns-token-not-set` if called before
    // APNs has handed back a token. Wait first; if it never arrives
    // within our budget, return and let onTokenRefresh catch it.
    if (Platform.isIOS) {
      final apnsReady = await _awaitApnsToken();
      if (!apnsReady || !await _ownsLifecycle(operationEpoch, identity)) {
        debugPrint('[FCM] APNs not ready within budget — '
            'onTokenRefresh will register the token when it arrives');
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
      debugPrint('[FCM] initial getToken exhausted retries — '
          'relying on onTokenRefresh');
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
          '[FCM] APNs token not yet available (attempt $attempt/$maxAttempts)');
      await Future<void>.delayed(Duration(seconds: attempt));
    }
    return false;
  }

  Future<void> _register(
    String token, {
    AuthSessionIdentity? expectedIdentity,
  }) async {
    final identity = expectedIdentity ??
        (await _ref.read(appTokenStorageProvider).readTokenSnapshot()).identity;
    if (identity == null) {
      debugPrint('[FCM] no active session — skipping device registration');
      return;
    }
    if ((await _ref.read(appTokenStorageProvider).readTokenSnapshot())
            .identity !=
        identity) {
      return;
    }
    final role = identity.role;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _ref.read(notificationServiceProvider).registerDevice(
              fcmToken: token,
              platform: _platform,
              role: role,
              expectedIdentity: identity,
            );
        if ((await _ref.read(appTokenStorageProvider).readTokenSnapshot())
                .identity ==
            identity) {
          _deviceRegistrationIdentity = identity;
        }
        debugPrint('[FCM] token registered (role=$role, attempt $attempt)');
        return;
      } catch (e) {
        debugPrint('[FCM] register attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    debugPrint('[FCM] register exhausted retries — token NOT registered');
  }

  void _wireVoipBridge(AuthSessionIdentity identity) {
    _voipEventSub ??= VoipCallBridgeService.instance.events.listen((event) {
      switch (event.type) {
        case VoipCallBridgeEventType.tokenUpdated:
          final token = event.token;
          if (token != null && token.isNotEmpty) {
            unawaited(
              _registerVoipToken(token, expectedIdentity: identity),
            );
          }
        case VoipCallBridgeEventType.tokenInvalidated:
          unawaited(
            _unregisterVoipToken(
              event.token,
              expectedIdentity: identity,
            ),
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
    _ref.read(routerProvider).go(AppRoutes.inAppCallPath(callId));
  }

  String _routeAfterCall(AppCallSession session) {
    return switch (session.bookingType) {
      'ride' => AppRoutes.rideTracking,
      'artisan_job' ||
      'job' when session.bookingId.isNotEmpty =>
        AppRoutes.jobActivePath(session.bookingId),
      _ => AppRoutes.home,
    };
  }

  void _navigateAfterCall(AppCallSession session) {
    final router = _ref.read(routerProvider);
    if ((session.bookingType == 'artisan_job' ||
            session.bookingType == 'job') &&
        session.bookingId.isNotEmpty) {
      router.go(AppRoutes.activity);
      router.push(AppRoutes.jobActivePath(session.bookingId));
      return;
    }
    router.go(_routeAfterCall(session));
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
    final router = _ref.read(routerProvider);
    router.go(AppRoutes.inAppCallPath(callId));
    try {
      final session = await _retryVoipAction(
        () => _ref.read(appCallServiceProvider).acceptCall(callId),
      );
      router.go(AppRoutes.inAppCallPath(callId), extra: session);
      await VoipCallBridgeService.instance
          .acknowledgeCallAction(event.actionId);
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
        await VoipCallBridgeService.instance
            .acknowledgeCallAction(event.actionId);
      } catch (cleanupError) {
        debugPrint('[VoIP] accept recovery acknowledge failed: $cleanupError');
      }
      router.go(AppRoutes.home);
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
      _navigateAfterCall(session);
      await VoipCallBridgeService.instance
          .acknowledgeCallAction(event.actionId);
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
      _navigateAfterCall(session);
      await VoipCallBridgeService.instance
          .acknowledgeCallAction(event.actionId);
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
        await _ref.read(notificationServiceProvider).registerVoipDevice(
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
      await _ref.read(notificationServiceProvider).unregisterVoipDevice(
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

  String get _platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// Cancel subs and delete the device token so the next account on this
  /// device registers a fresh binding.
  Future<void> dispose() async {
    final operationEpoch = ++_lifecycleEpoch;
    final deviceOwner = _deviceRegistrationIdentity;
    final voipOwner = _voipRegistrationIdentity;
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

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref);
});

/// Watches auth state and syncs the FCM token with the backend when the
/// user reaches [AuthAuthenticated]. On logout, deletes the token so the
/// next account on this device registers fresh.
///
/// Must be watched once at app start (e.g. `container.read(...)` in main)
/// so the subscription survives.
final fcmAuthBridgeProvider = Provider<void>((ref) {
  final authState = ref.watch(clientAuthControllerProvider);
  final fcm = ref.read(fcmServiceProvider);
  debugPrint('[FCM-bridge] auth state = ${authState.runtimeType}');

  if (authState is AuthAuthenticated) {
    debugPrint('[FCM-bridge] firing syncToken()');
    fcm.syncToken();
  } else if (authState is AuthUnauthenticated) {
    // Only delete the local token on explicit logout. Other transient
    // states (AuthUnknown on cold start, AuthOtpSent during login) used
    // to call dispose() too, which churned the token and raced syncToken.
    debugPrint('[FCM-bridge] firing dispose() (logout)');
    fcm.dispose();
  }
});

/// Wires FCM taps into GoRouter navigation. Must be read once AFTER the
/// router provider is built so `routerProvider` can resolve.
///
/// Routing table:
///   ride_* (+ rideId)           → /ride/tracking  (live trip screen)
///   job_artisan_arrived +jobId  → /services/job/:jobId/tracking  (urgent)
///   job_marked_complete +jobId  → /services/job/:jobId/summary   (confirm)
///   job_* (+ jobId)             → /services/job/:jobId           (detail)
///   job_bid_submitted + jobId   → /services/job/:jobId
///   new_message + jobId/rideId  → relevant tracking screen
///   payment_confirmed           → /activity
///   everything else             → /activity
final fcmTapBridgeProvider = Provider<void>((ref) {
  final fcm = ref.read(fcmServiceProvider);

  Future<bool> waitForAuthenticatedCall(
    String callId,
    Map<String, dynamic> payload,
  ) async {
    final initialRemaining = _remainingCallTimeout(payload);
    if (initialRemaining <= Duration.zero) return false;
    final deadline = DateTime.now().add(initialRemaining);
    while (DateTime.now().isBefore(deadline)) {
      final authState = ref.read(clientAuthControllerProvider);
      if (authState is AuthAuthenticated) {
        return _remainingCallTimeout(payload) > Duration.zero &&
            !await _hasTerminalCallTombstone(callId);
      }
      if (authState is AuthUnauthenticated) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  // Two-step navigation for deep-links: first land on the activity tab so
  // the navigator has at least one route, then push the detail screen on
  // top. Without the leading `go`, `router.go(detailPath)` replaces the
  // entire stack with the detail and tapping back throws
  // `GoError: There is nothing to pop`. Detail routes here use
  // `parentNavigatorKey: _rootNavigatorKey` (top-level overlays, not
  // nested under the shell), so the parent stack isn't reconstructed
  // automatically — we have to seed it.
  void pushDeepLink(GoRouter router, String path, {Object? extra}) {
    router.go(AppRoutes.activity);
    router.push(path, extra: extra);
  }

  fcm.onTapMessage = (payload) async {
    final router = ref.read(routerProvider);
    final rawType = payload[NotificationPayload.keyType] as String?;
    // Backend emits dotted types ("job.bid_received") in the FCM data
    // payload. The local-notification path normalises before re-encoding,
    // but the direct paths (onMessageOpenedApp + getInitialMessage) hand
    // us the raw `message.data` map — so we have to normalise here too,
    // otherwise every background / cold-start tap fell through to the
    // default case and dumped the user on /activity.
    final type =
        rawType == null ? null : NotificationPayload.normaliseType(rawType);
    final jobId = payload[NotificationPayload.keyJobId] as String?;
    final rideId = payload[NotificationPayload.keyRideId] as String?;
    debugPrint(
        '[FCM-tap] type=$type (raw=$rawType) jobId=$jobId rideId=$rideId');

    switch (type) {
      case NotificationPayload.typeAnnouncement:
        router.go(
          clientAnnouncementRoute(
            payload[NotificationPayload.keyDestination],
          ),
        );
        break;

      case NotificationPayload.typeCallIncoming:
        final callId = payload['callId'] as String?;
        if (callId == null || callId.isEmpty) {
          debugPrint('[FCM-tap] call_incoming missing callId: $payload');
          router.go(AppRoutes.activity);
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
        router.go(AppRoutes.inAppCallPath(callId));
        break;

      // ── Ride timeline ─────────────────────────────────────────────────
      case NotificationPayload.typeRideDriverAssigned:
        pushDeepLink(router, AppRoutes.rideDriverFound);
        break;
      case NotificationPayload.typeRideDriverEnRoute:
      case NotificationPayload.typeRideDriverArrived:
      case NotificationPayload.typeRideInProgress:
        pushDeepLink(router, AppRoutes.rideTracking);
        break;
      case NotificationPayload.typeRideCompleted:
        if (rideId != null) {
          pushDeepLink(router, AppRoutes.rideReceiptPath(rideId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeRideCancelled:
        router.go(AppRoutes.activity);
        break;

      // ── Job / artisan timeline ────────────────────────────────────────
      case NotificationPayload.typeJobBidSubmitted:
        if (jobId != null) {
          pushDeepLink(router, AppRoutes.jobDetailPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      // En route is the only phase where the live map is the right
      // landing — the user is checking "is the artisan close yet?".
      case NotificationPayload.typeJobArtisanEnRoute:
        if (jobId != null) {
          pushDeepLink(router, AppRoutes.jobTrackingPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      // Once the artisan has arrived / started / marked complete, the
      // request timeline is what the user wants — it carries the phase-
      // driven CTA ("Confirm, proceed to payment") that drives the next
      // step. The map-only tracking screen is useless past the en-route
      // phase. Note: the 'arrived' phase no longer surfaces a
      // confirm-arrival CTA — `_parsePhase` collapses it into
      // `inProgress` so the work session starts implicitly.
      case NotificationPayload.typeJobArtisanArrived:
      case NotificationPayload.typeJobInProgress:
      case NotificationPayload.typeJobMarkedComplete:
      case NotificationPayload.typeJobConfirmCompletionRequested:
        if (jobId != null) {
          pushDeepLink(router, AppRoutes.jobActivePath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobCompleted:
      case NotificationPayload.typeJobForceCompleted:
        if (jobId != null) {
          pushDeepLink(router, AppRoutes.jobCompletePath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobSupplementRequested:
        if (jobId != null) {
          pushDeepLink(router, AppRoutes.jobSupplementPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      // Reminders, staleness pings and no-show / no-bid escalations all
      // land on the job detail so the client can take the next action
      // (rebook, nudge, leave a check-in note).
      case NotificationPayload.typeJobReminder2h:
      case NotificationPayload.typeJobCheckin8h:
      case NotificationPayload.typeJobStale24h:
      case NotificationPayload.typeJobStale48h:
      case NotificationPayload.typeJobNoBidsEscalated:
      case NotificationPayload.typeJobArtisanNoShow:
        if (jobId != null) {
          pushDeepLink(router, AppRoutes.jobDetailPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobCancelled:
      case NotificationPayload.typeJobCancelledByArtisan:
        router.go(AppRoutes.activity);
        break;

      // ── Cross-cutting ─────────────────────────────────────────────────
      case NotificationPayload.typeNewMessage:
        // Push directly into the chat screen for the booking the message
        // belongs to. Falls back to /activity when the payload is missing
        // the booking ids — same defensive default as the rest of the
        // routing table.
        final rawBookingType =
            payload[NotificationPayload.keyBookingType] as String?;
        final bookingType = ChatBookingType.fromWire(rawBookingType);
        final bookingId =
            (payload[NotificationPayload.keyBookingId] as String?) ??
                (bookingType == ChatBookingType.ride ? rideId : jobId);
        if (bookingType == null || bookingId == null || bookingId.isEmpty) {
          router.go(AppRoutes.activity);
          break;
        }
        // Hydrate the peer (driver/artisan) details from the booking so
        // the chat screen header renders the same way it does when
        // opened from the active-ride / job-tracking surfaces. The FCM
        // payload only carries the notification title (usually "New
        // message"), which would otherwise blank out the peer card.
        String peerName = 'Chat';
        String peerStatus = '';
        try {
          if (bookingType == ChatBookingType.ride) {
            final raw = await ref.read(rideServiceProvider).getRide(bookingId);
            final driver =
                raw['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};
            final name = (driver['name'] as String?)?.trim();
            if (name != null && name.isNotEmpty) peerName = name;
            peerStatus = _ridePeerStatusFor(raw['status'] as String?);
          } else {
            final raw = await ref.read(jobServiceProvider).getJob(bookingId);
            final artisan =
                raw['artisan'] as Map<String, dynamic>? ?? <String, dynamic>{};
            final name = ((artisan['businessName'] ??
                    artisan['fullName'] ??
                    artisan['name']) as String?)
                ?.trim();
            if (name != null && name.isNotEmpty) peerName = name;
            peerStatus = _jobPeerStatusFor(raw['status'] as String?);
          }
        } catch (e) {
          debugPrint('[FCM] hydrate booking for chat failed: $e');
        }
        router.push(
          AppRoutes.chat,
          extra: <String, Object?>{
            'bookingType': bookingType,
            'bookingId': bookingId,
            'peerName': peerName,
            'peerStatus': peerStatus,
          },
        );
        break;

      // Backend asks the client to rate the counter-party for a completed
      // booking. Land on the screen that hosts the rating context
      // (ride receipt for rides, job complete for jobs) AND directly
      // open the rate sheet over it — matching the provider app's UX
      // where a tap on the push lands on the sheet, not on a screen
      // that requires another tap to start rating.
      case NotificationPayload.typeRatingPrompt:
        final bookingType =
            payload[NotificationPayload.keyBookingType] as String?;
        final bookingId = payload[NotificationPayload.keyBookingId] as String?;
        if (bookingType == 'ride') {
          final id = bookingId ?? rideId;
          if (id == null) {
            router.go(AppRoutes.activity);
            break;
          }
          // If the completion summary for this ride is still in memory,
          // land there instead — its OK flow runs summary → rating →
          // receipt, and auto-opening the sheet here would cover the fare
          // summary before the rider has read it.
          final summary = ref.read(rideReceiptProvider);
          if (summary != null && summary.rideId == id) {
            router.go(AppRoutes.rideComplete);
            break;
          }
          // Cold start / historical ride: the summary state is gone, so the
          // receipt is the rating context — open the sheet over it.
          pushDeepLink(router, AppRoutes.rideReceiptPath(id));
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final ctx = router.routerDelegate.navigatorKey.currentContext;
          if (ctx == null) break;
          var firstName = 'Driver';
          try {
            final raw = await ref.read(rideServiceProvider).getRide(id);
            final driver = raw['driver'];
            if (driver is Map<String, dynamic>) {
              final name = driver['name'] as String?;
              if (name != null && name.trim().isNotEmpty) {
                firstName = name.trim().split(RegExp(r'\s+')).first;
              }
            }
          } catch (e) {
            debugPrint('[FCM] hydrate ride for rating failed: $e');
          }
          if (!ctx.mounted) break;
          await showRateRideSheet(
            ctx,
            rideId: id,
            driverFirstName: firstName,
          );
        } else if (bookingType == 'artisan_job' || bookingType == 'job') {
          final id = bookingId ?? jobId;
          if (id == null) {
            router.go(AppRoutes.activity);
            break;
          }
          pushDeepLink(router, AppRoutes.jobCompletePath(id));
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final ctx = router.routerDelegate.navigatorKey.currentContext;
          if (ctx == null) break;
          var firstName = 'Artisan';
          try {
            final raw = await ref.read(jobServiceProvider).getJob(id);
            final artisan = raw['artisan'];
            if (artisan is Map<String, dynamic>) {
              final name = (artisan['displayName'] ??
                  artisan['businessName'] ??
                  artisan['fullName'] ??
                  artisan['name']) as String?;
              if (name != null && name.trim().isNotEmpty) {
                firstName = name.trim().split(RegExp(r'\s+')).first;
              }
            }
          } catch (e) {
            debugPrint('[FCM] hydrate job for rating failed: $e');
          }
          if (!ctx.mounted) break;
          await showRateJobSheet(
            ctx,
            jobId: id,
            artisanFirstName: firstName,
          );
          // After the client rates, drop them on the request details
          // page so they can review the booking, message the artisan,
          // or download the receipt — same final destination as the
          // post-payment dialog and the socket-driven prompt.
          if (ctx.mounted) {
            router.go(AppRoutes.jobDetailPath(id));
          }
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      // ── Support tickets ───────────────────────────────────────────────
      case NotificationPayload.typeSupportTicketMessage:
      case NotificationPayload.typeSupportTicketStatusChanged:
        final ticketId = payload[NotificationPayload.keyTicketId] as String?;
        if (ticketId != null && ticketId.isNotEmpty) {
          router.push(AppRoutes.supportTicketDetailPath(ticketId));
        } else {
          router.go(AppRoutes.supportTickets);
        }
        break;

      case NotificationPayload.typePaymentConfirmed:
      default:
        router.go(AppRoutes.activity);
    }
  };
});

/// Renders a friendly "what is the driver up to right now" string for
/// the chat header. Mirrors the labels the active-ride screen passes
/// when it opens the chat, so a notification-tap and an in-app tap
/// land on the same UI.
String _ridePeerStatusFor(String? rideStatus) {
  switch (rideStatus) {
    case 'accepted':
    case 'driver_en_route':
      return 'On the way';
    case 'arrived':
      return 'At pickup';
    case 'in_progress':
      return 'On your trip';
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
      return 'Reviewing your bids';
    case 'awarded':
    case 'accepted':
    case 'en_route':
    case 'driver_en_route':
      return 'On the way';
    case 'arrived':
      return 'On site';
    case 'in_progress':
      return 'On your job';
    case 'artisan_marked_complete':
      return 'Awaiting your confirmation';
    case 'completed':
      return 'Job completed';
    case 'cancelled':
      return 'Job cancelled';
    default:
      return '';
  }
}
