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
  final rawType = data[NotificationPayload.keyType] as String?;
  if (rawType == null || rawType.isEmpty) return;

  // Backend emits `job.bid_accepted`; mobile uses `job_bid_accepted`.
  final type = NotificationPayload.normaliseType(rawType);

  final title = message.notification?.title ?? data['title'] as String? ?? '';
  final body = message.notification?.body ?? data['body'] as String? ?? '';

  // Forward every data-key besides title/body/type so the tap handler can
  // read jobId / rideId / bidId / chatId / notificationId without losing
  // context.
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
  );
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
      return 'Job cancelled';
    case NotificationPayload.typeJobConfirmedComplete:
      return 'Job confirmed';
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
      return 'The client cancelled this job.';
    case NotificationPayload.typeRideCancelled:
      return 'The client cancelled this ride.';
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
      _markNotificationRead(payload);
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
      _markNotificationRead(payload);
      onTapMessage?.call(payload);
    });

    // Cold-start tap: app was terminated, user tapped a push to open it.
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] initial message: ${initialMessage.data}');
      final payload = Map<String, dynamic>.from(initialMessage.data);
      _markNotificationRead(payload);
      // Defer until the router is ready to avoid navigating before the
      // first frame.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        onTapMessage?.call(payload);
      });
    }
  }

  /// Fires a best-effort `PATCH /notifications/:id/read` when the push
  /// carries a `notificationId`. Clears the in-app bell in the background
  /// so a tap also settles the inbox. Swallows errors — the user has
  /// already acted, we just didn't get to record it.
  void _markNotificationRead(Map<String, dynamic> payload) {
    final id = payload[NotificationPayload.keyNotificationId] as String?;
    if (id == null || id.isEmpty) return;
    _ref
        .read(apiNotificationServiceProvider)
        .markAsRead(id)
        .catchError((Object e) {
      debugPrint('[FCM] markAsRead($id) failed: $e');
    });
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

  fcm.onTapMessage = (payload) async {
    final type = payload[NotificationPayload.keyType] as String?;
    final router = ref.read(goRouterProvider);

    switch (type) {
      case NotificationPayload.typeJobRequest:
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
        break;

      case NotificationPayload.typeRideRequest:
        // Rides: open the shell to home — the active-ride screen is
        // driven by separate state and the driver will see it immediately
        // via the socket listener once the app is foreground.
        router.go('/home');
        break;

      case NotificationPayload.typeBidAccepted:
      case NotificationPayload.typeSupplementApproved:
      case NotificationPayload.typeSupplementRejected:
        // Artisan has an active job waiting — go to the active-job screen
        // so they can advance the timeline.
        router.go('/active-job');
        break;

      case NotificationPayload.typeRideSettled:
      case NotificationPayload.typePaymentReceived:
        router.go('/earnings');
        break;

      case NotificationPayload.typeNewMessage:
        router.go('/messages');
        break;

      case NotificationPayload.typeBidRejected:
      case NotificationPayload.typeJobCancelled:
      case NotificationPayload.typeRideCancelled:
      case NotificationPayload.typeJobConfirmedComplete:
      default:
        router.go('/home');
    }
  };
});
