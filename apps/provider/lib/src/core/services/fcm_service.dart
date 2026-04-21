import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../app/router.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../di/providers.dart';
import 'local_notification_service.dart';

/// Background isolate handler — must be a top-level function annotated with
/// `@pragma('vm:entry-point')`.
///
/// When the app is terminated or the user is in another app, FCM spins up
/// a short-lived isolate, calls this, and then tears it down. We use it to
/// display a local notification (FCM alone would show a default system one
/// without tap payload).
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // Re-initialise the local notification plugin inside this isolate —
  // state from the main isolate is NOT shared.
  await LocalNotificationService.instance.init();
  await _renderFromRemote(message);
}

Future<void> _renderFromRemote(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] as String?;
  final title = message.notification?.title ?? data['title'] as String? ?? '';
  final body = message.notification?.body ?? data['body'] as String? ?? '';

  if (type == NotificationPayload.typeJobRequest) {
    final jobId = data[NotificationPayload.keyJobId] as String?;
    if (jobId == null) return;
    await LocalNotificationService.instance.showJobRequest(
      jobId: jobId,
      title: title.isEmpty ? 'New job request' : title,
      body: body.isEmpty ? 'A client has requested your services.' : body,
    );
  } else if (type == NotificationPayload.typeRideRequest) {
    final rideId = data[NotificationPayload.keyRideId] as String?;
    if (rideId == null) return;
    await LocalNotificationService.instance.showRideRequest(
      rideId: rideId,
      title: title.isEmpty ? 'New ride request' : title,
      body: body.isEmpty ? 'A passenger needs a ride.' : body,
    );
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
/// payload carries `{ type, jobId | rideId }` so the router can deep-link.
class FcmService {
  FcmService(this._ref);

  final Ref _ref;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialised = false;

  /// Called with the payload map when a user taps a push (either from the
  /// background/terminated state or after a foreground message surfaces
  /// through [LocalNotificationService]).
  void Function(Map<String, dynamic> payload)? onTapMessage;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // Background isolate handler MUST be registered before any message
    // can arrive. Safe to call multiple times.
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    // Permission prompts (iOS + Android 13+).
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Ensure tapping a local notification also routes via the same
    // handler the router will set.
    LocalNotificationService.instance.onTap = (payload) {
      onTapMessage?.call(payload);
    };

    // Foreground messages — the in-app modal is driven by the socket in
    // IncomingRequestListener, so we just surface a local notification as
    // a fallback (useful if the socket is disconnected).
    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint('[FCM] foreground message: ${message.data}');
      await _renderFromRemote(message);
    });

    // User tapped a push while the app was backgrounded → resumed.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[FCM] opened from background: ${message.data}');
      final payload = Map<String, dynamic>.from(message.data);
      onTapMessage?.call(payload);
    });

    // Cold-start tap: app was terminated, user tapped a push to open it.
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] initial message: ${initialMessage.data}');
      // Defer until the router is ready to avoid navigating before the
      // first frame.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        onTapMessage?.call(Map<String, dynamic>.from(initialMessage.data));
      });
    }
  }

  /// Fetch the FCM token and POST it to the backend so we can receive
  /// pushes. Call once the user is authenticated (needs JWT on the Dio
  /// client). Also subscribes to token refresh events.
  Future<void> syncToken() async {
    final token = await _fcm.getToken();
    if (token == null) {
      debugPrint('[FCM] token unavailable — skipping backend register');
      return;
    }
    await _register(token);

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fcm.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    try {
      await _ref.read(apiNotificationServiceProvider).registerDevice(
            fcmToken: token,
            platform: _platform,
          );
      debugPrint('[FCM] token registered with backend');
    } catch (e) {
      debugPrint('[FCM] register failed: $e');
    }
  }

  String get _platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// Remove backend registration + cancel listeners. Call on logout so the
  /// user's next account on this device gets its own fresh token binding.
  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    try {
      await _fcm.deleteToken();
    } catch (_) {
      // best-effort
    }
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref);
});

/// Watches the auth state and synchronises the FCM token with the backend
/// as soon as the user reaches `AuthAuthenticated`. On logout it clears
/// the device token so the next account on this device registers a fresh
/// binding.
///
/// Must be watched once at app start (e.g. `container.read(...)` in main)
/// so it stays subscribed.
final fcmAuthBridgeProvider = Provider<void>((ref) {
  final authState = ref.watch(authControllerProvider);
  final fcm = ref.read(fcmServiceProvider);

  if (authState is AuthAuthenticated) {
    fcm.syncToken();
  } else {
    // Fire-and-forget — don't block the auth transition on FCM cleanup.
    fcm.dispose();
  }
});

/// Wires FCM notification taps into GoRouter navigation.
///
/// When the user taps a push (background, terminated, or our own local
/// notification), this handler:
///   1. Extracts the payload `{ type, jobId | rideId }`
///   2. Fetches the full [Job] via `GET /jobs/:id`
///   3. Navigates to `/job-request` with the job
///
/// If the fetch fails (network/404), bounces to `/home`.
///
/// Must be read once at app start AFTER the router has been created so
/// `goRouterProvider` is ready to receive navigation calls.
final fcmTapBridgeProvider = Provider<void>((ref) {
  final fcm = ref.read(fcmServiceProvider);

  fcm.onTapMessage = (payload) async {
    final type = payload[NotificationPayload.keyType];
    final router = ref.read(goRouterProvider);

    if (type == NotificationPayload.typeJobRequest) {
      final jobId = payload[NotificationPayload.keyJobId] as String?;
      if (jobId == null) {
        router.go('/home');
        return;
      }
      try {
        final data = await ref.read(jobServiceProvider).getJob(jobId);
        final job = Job.fromJson(data);
        router.push('/job-request', extra: job);
      } catch (e) {
        debugPrint('[FCM] tap fetch failed for job $jobId: $e');
        router.go('/home');
      }
    } else if (type == NotificationPayload.typeRideRequest) {
      // Rides: open the shell to home for now — the active-ride screen is
      // driven by separate state and the driver will see it immediately
      // via the socket listener once the app is foreground.
      router.go('/home');
    }
  };
});
