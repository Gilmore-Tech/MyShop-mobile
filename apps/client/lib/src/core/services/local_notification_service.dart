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
  static const keyBookingType = 'bookingType';
  static const keyBookingId = 'bookingId';

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
  /// Backend emits `job.bid_received`.
  static const typeJobBidSubmitted = 'job_bid_received';

  /// Artisan is en route to the job location.
  static const typeJobArtisanEnRoute = 'job_artisan_en_route';

  /// Artisan arrived at the site — urgent.
  static const typeJobArtisanArrived = 'job_artisan_arrived';

  /// Artisan started the job. Backend emits `job.work_started`.
  static const typeJobInProgress = 'job_work_started';

  /// Artisan marked the job complete — waiting on client confirmation (urgent).
  /// Backend emits `job.artisan_marked_complete`.
  static const typeJobMarkedComplete = 'job_artisan_marked_complete';

  /// Backend nudges the client to confirm the artisan's "marked complete"
  /// when the auto-confirm window approaches. Same destination as
  /// [typeJobMarkedComplete] (urgent).
  static const typeJobConfirmCompletionRequested =
      'job_confirm_completion_requested';

  /// Job fully completed — settled. Currently only emitted to the
  /// provider per backend audit; kept here for forward-compat.
  static const typeJobCompleted = 'job_completed';

  /// Job cancelled — generic. Backend may also send the more specific
  /// `job.cancelled_by_artisan`; either renders the same way.
  static const typeJobCancelled = 'job_cancelled';

  /// Artisan cancelled an active job — specific variant of
  /// [typeJobCancelled] preserved when the backend wants to attribute
  /// blame in copy.
  static const typeJobCancelledByArtisan = 'job_cancelled_by_artisan';

  /// Backend force-completed a stale job (admin path / payment release
  /// trigger). Routes to the completed view so the client can dispute.
  static const typeJobForceCompleted = 'job_force_completed';

  /// No bids on an open job after the matching window — admin will pick
  /// up assignment. Tap takes the client to the job detail to add notes.
  static const typeJobNoBidsEscalated = 'job_no_bids_escalated';

  /// Artisan didn't show up for a scheduled job — urgent. Tap routes to
  /// the job detail so the client can rebook or escalate.
  static const typeJobArtisanNoShow = 'job_artisan_no_show';

  /// 8-hour check-in nudge during a multi-day job.
  static const typeJobCheckin8h = 'job_checkin_8h';

  /// 24-hour staleness reminder (no progress recorded).
  static const typeJobStale24h = 'job_stale_24h';

  /// 48-hour staleness escalation (auto-cancellation imminent).
  static const typeJobStale48h = 'job_stale_48h';

  /// 2-hour pre-job reminder (urgent — the job starts soon).
  static const typeJobReminder2h = 'job_reminder_2h';

  /// Artisan submitted a supplement (additional cost) request.
  static const typeJobSupplementRequested = 'job_supplement_requested';

  // ── Cross-cutting ────────────────────────────────────────────────────────
  /// New chat message from the counter-party.
  static const typeNewMessage = 'new_message';

  /// Payment confirmation / receipt available.
  static const typePaymentConfirmed = 'payment_confirmed';

  /// Backend asks the user to rate the counter-party for a completed
  /// booking. Payload carries `bookingType` (`ride` | `artisan_job`) and
  /// `bookingId`. Tapping deep-links to the rating screen pre-filled.
  static const typeRatingPrompt = 'rating_prompt';

  /// Generic / info — routes to notification inbox.
  static const typeGeneric = 'generic';

  // ── Support tickets ──────────────────────────────────────────────────────
  /// New message from a support agent on an open ticket. Payload carries
  /// `ticketId` (+ optional `messageId` for read tracking).
  static const typeSupportTicketMessage = 'support_ticket_message';

  /// Ticket status flipped server-side (resolved by agent, etc.). Same
  /// `ticketId` payload — taps deep-link to the same detail screen.
  static const typeSupportTicketStatusChanged = 'support_ticket_status_changed';

  /// Payload key for support deeplinks.
  static const keyTicketId = 'ticketId';
  static const keyMessageId = 'messageId';

  /// Types that deserve a heads-up, full-screen-intent style banner.
  static const Set<String> urgentTypes = {
    typeRideDriverAssigned,
    typeRideDriverArrived,
    typeJobArtisanArrived,
    typeJobMarkedComplete,
    typeJobConfirmCompletionRequested,
    typeJobReminder2h,
    typeJobArtisanNoShow,
  };

  /// Types that should render through the dedicated `chat_messages` channel
  /// (Android) / `MESSAGE` category (iOS) so the OS treats them like
  /// conversational pings — time-sensitive but not call-style.
  static const Set<String> chatTypes = {typeNewMessage};
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
    description: 'Progress updates on your active rides, jobs and bids. '
        'Leave enabled to stay informed without interruption.',
    importance: Importance.high,
    playSound: true,
    enableVibration: false,
  );

  /// Chat messages — high importance (so the user can hear them) but no
  /// full-screen call-style banner. Same urgency tier the OS uses for
  /// SMS/IM, which lets iOS pair it with the `MESSAGE` category for the
  /// time-sensitive interruption level.
  static const AndroidNotificationChannel _chatChannel =
      AndroidNotificationChannel(
    'chat_messages',
    'Chat messages',
    description: 'New messages from your driver or artisan during an active '
        'booking.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
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
    await androidPlugin?.createNotificationChannel(_chatChannel);
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
    final isChat = NotificationPayload.chatTypes.contains(type);
    final channel = isUrgent
        ? _urgentChannel
        : isChat
            ? _chatChannel
            : _timelineChannel;

    final androidCategory = isUrgent
        ? AndroidNotificationCategory.call
        : isChat
            ? AndroidNotificationCategory.message
            : AndroidNotificationCategory.status;

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
          category: androidCategory,
          fullScreenIntent: isUrgent,
          autoCancel: true,
          ongoing: false,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // Pair the iOS category with the appropriate interruption tier:
          //   urgent  → time-sensitive (cuts through Focus modes)
          //   chat    → time-sensitive + MESSAGE (iOS treats it like SMS)
          //   default → active
          categoryIdentifier: isChat ? 'MESSAGE' : null,
          interruptionLevel: (isUrgent || isChat)
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
