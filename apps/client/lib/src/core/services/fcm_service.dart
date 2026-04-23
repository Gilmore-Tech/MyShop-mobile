import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../di/providers.dart';
import 'local_notification_service.dart';

/// Background isolate entry-point — FCM spawns a short-lived isolate to
/// call this when a push arrives while the app is terminated or in the
/// background. MUST be a top-level function tagged with
/// `@pragma('vm:entry-point')` or the AOT tree-shaker will drop it.
///
/// We re-initialise the local notification plugin here because isolate
/// state is NOT shared with the main isolate.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  await LocalNotificationService.instance.init();
  await _renderFromRemote(message);
}

Future<void> _renderFromRemote(RemoteMessage message) async {
  final data = message.data;
  final rawType = data[NotificationPayload.keyType] as String?;
  if (rawType == null || rawType.isEmpty) return;

  // Backend emits `ride.driver_assigned`; mobile uses `ride_driver_assigned`.
  final type = NotificationPayload.normaliseType(rawType);

  final title = message.notification?.title ?? data['title'] as String? ?? '';
  final body = message.notification?.body ?? data['body'] as String? ?? '';

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
    case NotificationPayload.typeJobCompleted:
      return 'Job complete';
    case NotificationPayload.typeJobCancelled:
      return 'Job cancelled';
    case NotificationPayload.typeJobSupplementRequested:
      return 'Supplement request';
    case NotificationPayload.typeNewMessage:
      return 'New message';
    case NotificationPayload.typePaymentConfirmed:
      return 'Payment received';
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
      return 'Confirm the work to release payment.';
    case NotificationPayload.typeJobBidSubmitted:
      return 'An artisan has placed a bid on your request.';
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
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialised = false;

  void Function(Map<String, dynamic> payload)? onTapMessage;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // Must be registered before any message can arrive.
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

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
    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint('[FCM] foreground message: ${message.data}');
      await _renderFromRemote(message);
    });

    // Tap on push while app was backgrounded → resumed.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('[FCM] opened from background: ${message.data}');
      final payload = Map<String, dynamic>.from(message.data);
      _markNotificationRead(payload);
      onTapMessage?.call(payload);
    });

    // Cold-start: app was terminated, launched by a push tap.
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] initial message: ${initialMessage.data}');
      final payload = Map<String, dynamic>.from(initialMessage.data);
      _markNotificationRead(payload);
      // Defer so the router is mounted before we try to navigate.
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
        .read(notificationServiceProvider)
        .markAsRead(id)
        .catchError((Object e) {
      debugPrint('[FCM] markAsRead($id) failed: $e');
    });
  }

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
      await _ref.read(notificationServiceProvider).registerDevice(
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

  /// Cancel subs and delete the device token so the next account on this
  /// device registers a fresh binding.
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

/// Watches auth state and syncs the FCM token with the backend when the
/// user reaches [AuthAuthenticated]. On logout, deletes the token so the
/// next account on this device registers fresh.
///
/// Must be watched once at app start (e.g. `container.read(...)` in main)
/// so the subscription survives.
final fcmAuthBridgeProvider = Provider<void>((ref) {
  final authState = ref.watch(clientAuthControllerProvider);
  final fcm = ref.read(fcmServiceProvider);

  if (authState is AuthAuthenticated) {
    fcm.syncToken();
  } else {
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

  fcm.onTapMessage = (payload) {
    final router = ref.read(routerProvider);
    final type = payload[NotificationPayload.keyType] as String?;
    final jobId = payload[NotificationPayload.keyJobId] as String?;
    final rideId = payload[NotificationPayload.keyRideId] as String?;

    switch (type) {
      // ── Ride timeline ─────────────────────────────────────────────────
      case NotificationPayload.typeRideDriverAssigned:
        router.go(AppRoutes.rideDriverFound);
        break;
      case NotificationPayload.typeRideDriverEnRoute:
      case NotificationPayload.typeRideDriverArrived:
      case NotificationPayload.typeRideInProgress:
        router.go(AppRoutes.rideTracking);
        break;
      case NotificationPayload.typeRideCompleted:
        if (rideId != null) {
          router.go(AppRoutes.rideReceiptPath(rideId));
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
          router.go(AppRoutes.jobDetailPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobArtisanEnRoute:
      case NotificationPayload.typeJobArtisanArrived:
      case NotificationPayload.typeJobInProgress:
        if (jobId != null) {
          router.go(AppRoutes.jobTrackingPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobMarkedComplete:
        if (jobId != null) {
          router.go(AppRoutes.jobSummaryPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobCompleted:
        if (jobId != null) {
          router.go(AppRoutes.jobCompletePath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobSupplementRequested:
        if (jobId != null) {
          router.go(AppRoutes.jobSupplementPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobCancelled:
        router.go(AppRoutes.activity);
        break;

      // ── Cross-cutting ─────────────────────────────────────────────────
      case NotificationPayload.typeNewMessage:
        if (jobId != null) {
          router.go(AppRoutes.jobTrackingPath(jobId));
        } else if (rideId != null) {
          router.go(AppRoutes.rideTracking);
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typePaymentConfirmed:
      default:
        router.go(AppRoutes.activity);
    }
  };
});
