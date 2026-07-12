import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../app/router.dart';
import '../../features/artisan_home/providers/active_job_provider.dart';
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_home/widgets/rate_client_sheet.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../../features/driver_home/widgets/rate_passenger_sheet.dart';
import '../di/providers.dart';
import '../providers/pending_request_recovery_provider.dart';
import '../providers/socket_provider.dart';
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
    'data=${message.data}',
  );
  // FCM auto-displays hybrid pushes (top-level `notification`) while the
  // app is backgrounded/terminated. For normal timeline/chat pushes that is
  // exactly what we want because rendering locally as well produces duplicate
  // banners. Incoming work/ride requests are the exception: on Android they
  // must use our local request channel so they stay sticky until timeout and
  // play the MyShop request ringtone. Backend should already send those as
  // Android data-only pushes, but this defensive branch keeps the provider
  // alert usable if any backend path still includes a notification field.
  if (_shouldSkipLocalBackgroundRender(message)) {
    debugPrint(
      '[FCM-bg] FCM SDK will auto-display non-request push — '
      'skipping local render',
    );
    return;
  }
  // Re-initialise the local notification plugin inside this isolate —
  // state from the main isolate is NOT shared.
  await LocalNotificationService.instance.init();
  await _renderFromRemote(message);
  debugPrint('[FCM-bg] local notification rendered');
}

bool _shouldSkipLocalBackgroundRender(RemoteMessage message) {
  if (message.notification == null) return false;

  final rawType = message.data[NotificationPayload.keyType]?.toString() ?? '';
  final type = NotificationPayload.normaliseType(rawType);

  final shouldUseLocalRequestAlert = Platform.isAndroid &&
      NotificationPayload.fullScreenRequestTypes.contains(type);
  if (shouldUseLocalRequestAlert) {
    debugPrint(
      '[FCM-bg] Android incoming request has notification field; '
      'rendering local sticky request alert anyway',
    );
    return false;
  }

  return true;
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
    case NotificationPayload.typeRatingPrompt:
      return 'Rate your client';
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
      return 'Your earnings are being released to your wallet.';
    case NotificationPayload.typeJobManuallyAssigned:
      return 'Tap to review and place your bid.';
    case NotificationPayload.typeJobNoBidsEscalated:
      return 'A nearby job needs an artisan. Tap to bid.';
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
    debugPrint('[FCM] init() called (initialised=$_initialised)');
    if (_initialised) return;
    _initialised = true;

    // Background isolate handler MUST be registered before any message
    // can arrive. Safe to call multiple times.
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    debugPrint('[FCM] background handler registered');

    // Permission prompts (iOS + Android 13+).
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Ensure tapping a local notification also routes via the same
    // handler the router will set.
    LocalNotificationService.instance.onTap = (payload) {
      _markNotificationRead(payload);
      onTapMessage?.call(payload);
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
    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint('[FCM] foreground message: ${message.data}');
      final rawType = message.data[NotificationPayload.keyType] as String?;
      final type = NotificationPayload.normaliseType(rawType ?? '');
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
      if (NotificationPayload.fullScreenRequestTypes.contains(type)) {
        debugPrint(
          '[FCM] foreground $type — handled by in-app modal, skipping banner',
        );
        return;
      }
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

    // Defense in depth: the auth bridge fires syncToken when state hits
    // AuthAuthenticated, but on cold start that can fire BEFORE init()
    // has requested permission — getToken() then returns null and the
    // single-shot bridge never re-fires. Kick it again now that perms
    // are granted; syncToken is idempotent (registerDevice is an upsert).
    final authState = _ref.read(authControllerProvider);
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
    _ref.read(apiNotificationServiceProvider).markAsRead(id).catchError((
      Object e,
    ) {
      debugPrint('[FCM] markAsRead($id) failed: $e');
    });
  }

  /// Fetch the FCM token and POST it to the backend so we can receive
  /// pushes. Call once the user is authenticated (needs JWT on the Dio
  /// client). Also subscribes to token refresh events.
  Future<void> syncToken() async {
    debugPrint('[FCM] syncToken() entered');

    // Register the token-refresh listener FIRST. On iOS, APNs registration
    // on a fresh install can take longer than our initial retry window.
    // If we exhaust retries here, the FCM token still arrives later via
    // onTokenRefresh — and we need the listener already wired so the
    // _register call fires the moment the token shows up.
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fcm.onTokenRefresh.listen(_register);

    // iOS: FCM derives its token from the APNs device token. On cold
    // start `getToken()` throws `apns-token-not-set` if called before
    // APNs has handed back a token. Wait first; if it never arrives
    // within our budget, return and let onTokenRefresh catch it.
    if (Platform.isIOS) {
      final apnsReady = await _awaitApnsToken();
      if (!apnsReady) {
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
    }
    if (token == null) {
      debugPrint(
        '[FCM] initial getToken exhausted retries — '
        'relying on onTokenRefresh',
      );
      return;
    }
    debugPrint('[FCM] obtained device token');
    await _register(token);
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

  Future<void> _register(String token) async {
    // Pull active role from secure storage. The backend keys
    // device_tokens on (userId, role, platform) — passing the wrong
    // role here silently routes another role's pushes to this device.
    // No role stored = no authenticated session, so skip registration.
    final role = await _ref.read(appTokenStorageProvider).readRole();
    if (role == null || role.isEmpty) {
      debugPrint('[FCM] no active role — skipping device registration');
      return;
    }
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _ref
            .read(apiNotificationServiceProvider)
            .registerDevice(fcmToken: token, platform: _platform, role: role);
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
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    try {
      await _fcm.deleteToken();
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
    final rawType = payload[NotificationPayload.keyType] as String?;
    // Backend emits dotted types ("job.request") in the FCM data payload.
    // The local-notification path normalises before re-encoding, but the
    // direct paths (onMessageOpenedApp + getInitialMessage) hand us the
    // raw `message.data` map — so we have to normalise here too, otherwise
    // every background / cold-start tap fell through to the default case.
    final type =
        rawType == null ? null : NotificationPayload.normaliseType(rawType);
    final router = ref.read(goRouterProvider);
    debugPrint('[FCM-tap] type=$type (raw=$rawType)');

    // Backend may send the job id under either `jobId` (camel) or
    // `job_id` (snake) depending on which emitter wrote the push.
    String? jobIdFromPayload() =>
        (payload[NotificationPayload.keyJobId] as String?) ??
        (payload['job_id'] as String?);

    DateTime? requestDeadlineFromPayload() {
      for (final key in const [
        'expiresAt',
        'expires_at',
        'acceptanceExpiresAt',
        'acceptance_expires_at',
        'requestExpiresAt',
        'request_expires_at',
      ]) {
        final raw = payload[key];
        if (raw is String && raw.isNotEmpty) {
          final parsed = DateTime.tryParse(raw);
          if (parsed != null) return parsed;
        }
      }

      final seconds = payload['expiresInSeconds'] ??
          payload['expires_in_seconds'] ??
          payload['acceptanceWindowSeconds'] ??
          payload['acceptance_window_seconds'];
      if (seconds is num && seconds > 0) {
        return DateTime.now().toUtc().add(Duration(seconds: seconds.toInt()));
      }
      return null;
    }

    // Shared landing path for every job-context tap that drops the user
    // on /active-job (bid accepted, supplement decisions, reminders,
    // welfare/stale check-ins). The slot is normally seeded when the
    // artisan taps "Accept & Start Job" on the bid-status banner; if
    // the trigger fired while the app was backgrounded/terminated, the
    // tap handler reaches this point with an empty slot and we have to
    // hydrate from GET /jobs/:id ourselves — otherwise the screen
    // renders its "No active job" empty state.
    Future<void> hydrateAndGoToActiveJob(String? jobId) async {
      if (jobId == null) {
        debugPrint('[FCM-tap] active-job tap: no jobId in payload');
        router.go('/active-job');
        return;
      }
      final cached = ref.read(activeJobProvider).job;
      if (cached?.id == jobId) {
        // Slot already holds this job (foreground socket path or a
        // prior tap kept it warm) — straight to the screen.
        router.go('/active-job');
        return;
      }
      // Land on /home during the fetch so the user isn't staring at
      // _NoActiveJob for the duration of the round-trip — that's
      // exactly the regression we're avoiding.
      router.go('/home');
      try {
        final data = await ref.read(jobServiceProvider).getJob(jobId);
        final job = Job.fromJson(data);
        ref.read(activeJobProvider.notifier).setJob(job);
        router.go('/active-job');
      } catch (e) {
        debugPrint('[FCM-tap] active-job hydrate failed for $jobId: $e');
        // Drop on My Jobs so the affected job is at least visible in
        // the list. Better than dumping the user on a blank screen.
        router.go('/trips');
      }
    }

    void openRideRequest(Ride ride) {
      final currentPath = router.routerDelegate.currentConfiguration.uri.path;
      debugPrint('[FCM-tap] opening /ride-request for ${ride.id}');
      if (currentPath == '/ride-request') {
        router.pushReplacement('/ride-request', extra: ride);
      } else {
        router.push('/ride-request', extra: ride);
      }
    }

    void openRideRequestLoader(String rideId, DateTime? deadline) {
      final currentPath = router.routerDelegate.currentConfiguration.uri.path;
      final extra = RideRequestRouteExtra(
        rideId: rideId,
        expiresAt: deadline,
      );
      debugPrint('[FCM-tap] opening /ride-request loader for $rideId');
      if (currentPath == '/ride-request') {
        router.pushReplacement('/ride-request', extra: extra);
      } else {
        router.push('/ride-request', extra: extra);
      }
    }

    Future<bool> recoverAndOpenPendingRideRequest(String reason) async {
      debugPrint('[FCM-tap] ride_request recovery: $reason');
      final recovered = await recoverPendingRideRequestFromRef(ref);
      if (recovered == null) {
        debugPrint('[FCM-tap] ride_request recovery found no active request');
        return false;
      }
      openRideRequest(recovered);
      return true;
    }

    bool requestDeadlineExpired(DateTime deadline) {
      return !DateTime.now().toUtc().isBefore(deadline.toUtc());
    }

    switch (type) {
      case NotificationPayload.typeJobRequest:
        // Backend may send the job id under either `jobId` (camel) or
        // `job_id` (snake) depending on which emitter wrote the push;
        // accept both so a casing drift doesn't silently route to /home.
        final jobId = (payload[NotificationPayload.keyJobId] as String?) ??
            (payload['job_id'] as String?);
        debugPrint('[FCM-tap] job_request jobId=$jobId payload=$payload');
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
        // Land on /home so dismissing /job-request returns to a sane
        // shell, then push the bid details synchronously with a stub
        // Job carrying only the id. JobRequestScreen.initState() calls
        // _hydrateJob() which fetches the full record from
        // GET /jobs/:id and rerenders — so the screen does the network
        // I/O itself, against its own loading lifecycle, instead of us
        // holding the FCM callback open while a Render cold-start
        // refresh runs to 60 seconds and the user sees nothing happen.
        router.go('/home');
        debugPrint('[FCM-tap] pushing /job-request stub for $jobId');
        router.push(
          '/job-request',
          extra: Job(
            id: jobId,
            status: JobStatus.open,
            categoryId: '',
            description: '',
            latitude: 0,
            longitude: 0,
          ),
        );
        break;

      case NotificationPayload.typeRideRequest:
        // Backend may send the ride id under `rideId` (camel) or `ride_id`
        // (snake) depending on which emitter wrote the push.
        final rideId = (payload[NotificationPayload.keyRideId] as String?) ??
            (payload['ride_id'] as String?);
        debugPrint('[FCM-tap] ride_request rideId=$rideId payload=$payload');
        if (rideId == null) {
          router.go('/home');
          debugPrint('[FCM-tap] no rideId in payload — running recovery');
          await recoverPendingRequestsNow(ref);
          break;
        }
        final deadline = requestDeadlineFromPayload();
        if (deadline != null) {
          ref.read(rideRequestDeadlineByIdProvider.notifier).update(
                (m) => {...m, rideId: deadline},
              );
          if (requestDeadlineExpired(deadline)) {
            debugPrint('[FCM-tap] ride_request $rideId expired before tap');
            router.go('/home');
            await recoverAndOpenPendingRideRequest('payload deadline expired');
            break;
          }
        }
        if (ref.read(visibleRideRequestIdProvider) == rideId) {
          debugPrint('[FCM-tap] ride_request $rideId already visible');
          break;
        }
        // Suppress the foreground re-broadcast modal for this ride — the
        // user already acknowledged by tapping the notification, so the
        // in-app sheet on top of /ride-request would be redundant.
        ref
            .read(surfacedRideIdsProvider.notifier)
            .update((s) => {...s, rideId});
        if (ref.read(incomingRideRequestProvider)?.id == rideId) {
          final cachedRide = ref.read(incomingRideRequestProvider);
          ref.read(incomingRideRequestProvider.notifier).state = null;
          if (cachedRide != null && cachedRide.status == RideStatus.requested) {
            openRideRequest(cachedRide);
            break;
          }
        }
        ref.read(rideRequestNavigationInFlightProvider.notifier).update(
              (s) => {...s, rideId},
            );
        openRideRequestLoader(rideId, deadline);
        ref.read(rideRequestNavigationInFlightProvider.notifier).update(
              (s) => {...s}..remove(rideId),
            );
        break;

      case NotificationPayload.typeBidAccepted:
      case NotificationPayload.typeSupplementApproved:
      case NotificationPayload.typeSupplementRejected:
        await hydrateAndGoToActiveJob(jobIdFromPayload());
        break;

      case NotificationPayload.typeRideSettled:
      case NotificationPayload.typePaymentReceived:
      case NotificationPayload.typeJobPaymentReleasing:
      // Client confirmed the work and the payout has been released —
      // earnings is where the artisan wants to land.
      case NotificationPayload.typeJobConfirmedComplete:
        router.go('/earnings');
        break;

      // Cancellations (client- or platform-initiated) — drop the user
      // on My Jobs / My Trips so they see the cancelled booking in
      // their list with the cancelled status, instead of a generic
      // home tab that gives no context.
      case NotificationPayload.typeJobCancelled:
      case NotificationPayload.typeJobCancelledByClient:
      case NotificationPayload.typeRideCancelled:
        router.go('/trips');
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
      // this artisan manually. Either way we want them to see the job
      // request screen so they can review and bid. Fetch the job first
      // so the screen can render context; bounce to /home on failure.
      case NotificationPayload.typeJobNoBidsEscalated:
      case NotificationPayload.typeJobManuallyAssigned:
        final jobId = payload[NotificationPayload.keyJobId] as String?;
        if (jobId == null) {
          router.go('/home');
          break;
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
          router.go('/messages');
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
        router.push(
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
          router.push('/account/support/tickets/$ticketId');
        } else {
          router.go('/account/support/tickets');
        }
        break;

      case NotificationPayload.typeBidRejected:
      default:
        router.go('/home');
    }
  };
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
