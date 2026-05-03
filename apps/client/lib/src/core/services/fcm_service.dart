import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' show ChatBookingType;

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
    //
    // `new_message` is the exception: the chat socket already delivers
    // the message and the in-app surfaces (active-ride/job header, the
    // chat screen, the unread badge on the entry-point button) reflect
    // it. Suppress the OS banner so we don't double-notify.
    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint('[FCM] foreground message: ${message.data}');
      final rawType = message.data[NotificationPayload.keyType] as String?;
      final type = NotificationPayload.normaliseType(rawType ?? '');
      if (type == NotificationPayload.typeNewMessage) {
        debugPrint('[FCM] foreground new_message — suppressing OS banner');
        return;
      }
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

    // Defense in depth: the auth bridge fires syncToken when state hits
    // AuthAuthenticated, but on cold start that can fire BEFORE init()
    // has requested permission — getToken() then returns null and the
    // single-shot bridge never re-fires. Kick it again now that perms
    // are granted; syncToken is idempotent (registerDevice is an upsert).
    final authState = _ref.read(clientAuthControllerProvider);
    if (authState is AuthAuthenticated) {
      unawaited(syncToken());
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
    String? token;
    for (int attempt = 1; attempt <= 3; attempt++) {
      token = await _fcm.getToken();
      if (token != null) break;
      debugPrint('[FCM] getToken null (attempt $attempt/3) — retrying');
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
    if (token == null) {
      debugPrint('[FCM] getToken exhausted retries — token unavailable');
      return;
    }
    debugPrint('[FCM] obtained token (last 12) …${token.substring(token.length - 12)}');
    await _register(token);

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fcm.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _ref.read(notificationServiceProvider).registerDevice(
              fcmToken: token,
              platform: _platform,
            );
        debugPrint('[FCM] token registered with backend (attempt $attempt)');
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
  } else if (authState is AuthUnauthenticated) {
    // Only delete the local token on explicit logout. Other transient
    // states (AuthUnknown on cold start, AuthOtpSent during login) used
    // to call dispose() too, which churned the token and raced syncToken.
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
      case NotificationPayload.typeJobConfirmCompletionRequested:
        if (jobId != null) {
          router.go(AppRoutes.jobSummaryPath(jobId));
        } else {
          router.go(AppRoutes.activity);
        }
        break;
      case NotificationPayload.typeJobCompleted:
      case NotificationPayload.typeJobForceCompleted:
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
          router.go(AppRoutes.jobDetailPath(jobId));
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
        router.push(
          AppRoutes.chat,
          extra: <String, Object?>{
            'bookingType': bookingType,
            'bookingId': bookingId,
            'peerName': payload['title'] as String? ?? 'Chat',
            'peerStatus': '',
          },
        );
        break;

      // Backend asks the client to rate the counter-party for a completed
      // booking. Land on the screen that already hosts the rating sheet
      // (ride receipt for rides, job complete for jobs); both either
      // auto-open the sheet or surface a clearly visible Rate CTA.
      case NotificationPayload.typeRatingPrompt:
        final bookingType =
            payload[NotificationPayload.keyBookingType] as String?;
        final bookingId = payload[NotificationPayload.keyBookingId] as String?;
        if (bookingType == 'ride') {
          final id = bookingId ?? rideId;
          if (id != null) {
            router.go(AppRoutes.rideReceiptPath(id));
          } else {
            router.go(AppRoutes.activity);
          }
        } else if (bookingType == 'artisan_job' || bookingType == 'job') {
          final id = bookingId ?? jobId;
          if (id != null) {
            router.go(AppRoutes.jobCompletePath(id));
          } else {
            router.go(AppRoutes.activity);
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
