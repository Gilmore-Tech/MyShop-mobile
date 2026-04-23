import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys + type constants embedded in local/FCM notification payloads. The
/// backend must send the SAME [keyType] string in `data` so the tap handler
/// can deep-link into the correct screen.
///
/// Keep in sync with [provider app: local_notification_service.dart] and the
/// backend notification emitter.
class NotificationPayload {
  static const keyType = 'type';
  static const keyJobId = 'jobId';
  static const keyRideId = 'rideId';
  static const keyBidId = 'bidId';
  static const keyChatId = 'chatId';
  static const keyNotificationId = 'notificationId';

  /// The backend sends types prefixed by domain with a dot separator
  /// (e.g. `ride.driver_assigned`, `job.bid_submitted`, `chat.message`).
  /// Normalise them to the underscore form used by the [type*] constants
  /// so the switch doesn't care which separator the emitter picked.
  static String normaliseType(String raw) => raw.replaceAll('.', '_');

  // ── Ride timeline (client-targeted) ──────────────────────────────────────
  /// A driver has been matched and assigned to the rider's booking.
  static const typeRideDriverAssigned = 'ride_driver_assigned';

  /// Assigned driver is now en route to the pickup.
  static const typeRideDriverEnRoute = 'ride_driver_en_route';

  /// Driver has arrived at the pickup — urgent, tap to view.
  static const typeRideDriverArrived = 'ride_driver_arrived';

  /// Ride has started (client is in the vehicle).
  static const typeRideInProgress = 'ride_in_progress';

  /// Ride completed — fare charged, receipt ready.
  static const typeRideCompleted = 'ride_completed';

  /// Ride was cancelled by the driver or the system.
  static const typeRideCancelled = 'ride_cancelled';

  // ── Job / artisan timeline (client-targeted) ─────────────────────────────
  /// A new bid was submitted on the rider's open job.
  static const typeJobBidSubmitted = 'job_bid_submitted';

  /// Artisan is en route to the job location.
  static const typeJobArtisanEnRoute = 'job_artisan_en_route';

  /// Artisan arrived at the site — urgent.
  static const typeJobArtisanArrived = 'job_artisan_arrived';

  /// Artisan started the job.
  static const typeJobInProgress = 'job_in_progress';

  /// Artisan marked the job complete — waiting on client confirmation (urgent).
  static const typeJobMarkedComplete = 'job_marked_complete';

  /// Job fully completed — settled.
  static const typeJobCompleted = 'job_completed';

  /// Job cancelled.
  static const typeJobCancelled = 'job_cancelled';

  /// Artisan submitted a supplement (additional cost) request.
  static const typeJobSupplementRequested = 'job_supplement_requested';

  // ── Cross-cutting ────────────────────────────────────────────────────────
  /// New chat message from the counter-party.
  static const typeNewMessage = 'new_message';

  /// Payment confirmation / receipt available.
  static const typePaymentConfirmed = 'payment_confirmed';

  /// Generic / info — routes to notification inbox.
  static const typeGeneric = 'generic';

  /// Types that deserve a heads-up, full-screen-intent style banner.
  static const Set<String> urgentTypes = {
    typeRideDriverAssigned,
    typeRideDriverArrived,
    typeJobArtisanArrived,
    typeJobMarkedComplete,
    typeNewMessage,
  };
}

/// Thin wrapper around `flutter_local_notifications`. Responsibilities:
///   • Register notification channels once on init.
///   • Render FCM pushes that arrive while the app is backgrounded or
///     terminated (FCM's default banner has no payload tap routing).
///   • Forward taps to whatever the router has registered via [onTap].
///
/// All timeline pushes use the same data-payload shape
/// `{type, jobId | rideId | bidId | chatId}` so a single tap handler can
/// deep-link regardless of which notification type fired.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Max importance — heads-up banner with sound. Used for urgent timeline
  /// steps the user must act on immediately (driver arrived, bid accepted,
  /// artisan marked complete, new chat message).
  static const AndroidNotificationChannel _urgentChannel =
      AndroidNotificationChannel(
    'myshop_urgent',
    'Urgent updates',
    description:
        'Time-sensitive updates — driver arrival, bid match, completion '
        'confirmations. Muting this may cause you to miss an active trip.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// High importance but non-intrusive — used for incremental status
  /// transitions (new bid submitted, driver en route, ride started, etc.).
  static const AndroidNotificationChannel _timelineChannel =
      AndroidNotificationChannel(
    'myshop_timeline',
    'Trip & job updates',
    description:
        'Progress updates on your active rides, jobs and bids. '
        'Leave enabled to stay informed without interruption.',
    importance: Importance.high,
    playSound: true,
    enableVibration: false,
  );

  bool _initialised = false;

  /// Router-owned tap handler. Forwards the decoded payload map.
  void Function(Map<String, dynamic> payload)? _onTap;
  set onTap(void Function(Map<String, dynamic> payload)? handler) =>
      _onTap = handler;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final decoded = json.decode(raw);
          if (decoded is Map<String, dynamic>) _onTap?.call(decoded);
        } catch (e) {
          debugPrint('[LocalNotificationService] bad payload: $e');
        }
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_urgentChannel);
    await androidPlugin?.createNotificationChannel(_timelineChannel);
    await androidPlugin?.requestNotificationsPermission();
  }

  /// Single entry-point for rendering any timeline push. Picks the right
  /// channel, styling and payload shape based on [type].
  ///
  /// [type] MUST be one of [NotificationPayload]'s `type*` constants.
  /// [extras] is merged into the payload — use it to pass ids like
  /// `{jobId: '...'}` or `{rideId: '...'}` so the tap handler can deep-link.
  Future<void> showTimelineUpdate({
    required String type,
    required String title,
    required String body,
    Map<String, String> extras = const {},
  }) async {
    final isUrgent = NotificationPayload.urgentTypes.contains(type);
    final channel = isUrgent ? _urgentChannel : _timelineChannel;

    await _plugin.show(
      _dedupeId(type, extras),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: isUrgent ? Importance.max : Importance.high,
          priority: isUrgent ? Priority.high : Priority.defaultPriority,
          category: isUrgent
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.status,
          fullScreenIntent: isUrgent,
          autoCancel: true,
          ongoing: false,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: isUrgent
              ? InterruptionLevel.timeSensitive
              : InterruptionLevel.active,
        ),
      ),
      payload: json.encode({
        NotificationPayload.keyType: type,
        ...extras,
      }),
    );
  }

  /// Fire system alert sound + haptic. Used when a modal already owns the
  /// foreground — no banner needed, but we still nudge the user.
  Future<void> playForegroundAlert() async {
    await HapticFeedback.heavyImpact();
    await SystemSound.play(SystemSoundType.alert);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await HapticFeedback.heavyImpact();
  }

  /// Stable non-negative notification id. Dedupes per `{type, primary-id}`
  /// so a status progression replaces the previous banner rather than
  /// stacking four notifications for the same ride.
  int _dedupeId(String type, Map<String, String> extras) {
    final primary = extras[NotificationPayload.keyRideId] ??
        extras[NotificationPayload.keyJobId] ??
        extras[NotificationPayload.keyChatId] ??
        extras[NotificationPayload.keyBidId] ??
        type;
    return ('$type:$primary').hashCode & 0x7fffffff;
  }
}

/// Exposed so widgets can `ref.read(...).playForegroundAlert()` or access
/// the singleton directly.
final localNotificationServiceProvider =
    Provider<LocalNotificationService>((_) {
  return LocalNotificationService.instance;
});
