import 'dart:async';
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
  static const keyCallId = 'callId';
  static const keyExpiresAt = 'expiresAt';
  static const keyDestination = 'destination';

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

  /// Admin-authored push campaign. Its destination is resolved through the
  /// local allowlist in [clientAnnouncementRoute].
  static const typeAnnouncement = 'announcement';

  /// In-app voice call fallback. iOS should route this through CallKit when
  /// Flutter receives it; background/locked iOS must still rely on PushKit.
  static const typeCallIncoming = 'call_incoming';

  /// Control-only push used to dismiss an unanswered incoming call after the
  /// caller hangs up. It must never render its own notification.
  static const typeCallEnded = 'call_ended';

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

  /// Types that deserve a persistent call-category notification.
  static const Set<String> urgentTypes = {
    typeCallIncoming,
    typeRideDriverAssigned,
    typeRideDriverArrived,
    typeJobArtisanArrived,
    typeJobMarkedComplete,
    typeJobConfirmCompletionRequested,
    typeJobReminder2h,
    typeJobArtisanNoShow,
  };

  static const Set<String> persistentCallTypes = {typeCallIncoming};

  /// Types that should render through the dedicated `chat_messages` channel
  /// (Android) / `MESSAGE` category (iOS) so the OS treats them like
  /// conversational pings — time-sensitive but not call-style.
  static const Set<String> chatTypes = {typeNewMessage};
}

/// Resolves an admin announcement destination without ever trusting a remote
/// path. App-store campaigns fall back to the inbox until the payload contract
/// includes a separately validated store URL.
String clientAnnouncementRoute(Object? rawDestination) {
  final destination = rawDestination?.toString().trim().toLowerCase();
  return switch (destination) {
    'activity' => '/activity',
    'support' => '/profile/support',
    'promotions' => '/home',
    'notifications' || 'app_store' => '/notifications',
    _ => '/notifications',
  };
}

const clientDashboardRoute = '/home';
const clientNotificationInboxRoute = '/notifications';
const clientTraySourceQueryKey = 'source';
const clientTraySourceQueryValue = 'tray';

/// Marks an inbox destination as originating from an operating-system tray
/// tap. The marker lets the inbox return to the Client dashboard even if a
/// platform resume or duplicate callback reconstructs an unexpected stack.
String clientTrayDestinationRoute(String destinationRoute) {
  final uri = Uri.tryParse(destinationRoute);
  if (uri == null || uri.path != clientNotificationInboxRoute) {
    return destinationRoute;
  }
  return uri.replace(
    queryParameters: <String, String>{
      ...uri.queryParameters,
      clientTraySourceQueryKey: clientTraySourceQueryValue,
    },
  ).toString();
}

bool clientNotificationOpenedFromTray(Uri uri) =>
    uri.path == clientNotificationInboxRoute &&
    uri.queryParameters[clientTraySourceQueryKey] == clientTraySourceQueryValue;

/// A system-tray tap starts a fresh navigation intent. Seed the authenticated
/// dashboard before presenting the destination so Back has a deterministic,
/// safe place to return to. In-app inbox taps do not use this stack; they push
/// onto the user's existing navigation history instead.
List<String> clientTrayNavigationStack(String destinationRoute) {
  if (destinationRoute == clientDashboardRoute) {
    return const [clientDashboardRoute];
  }
  return [clientDashboardRoute, clientTrayDestinationRoute(destinationRoute)];
}

/// The only operations an inbox row may expose to the Client UI.
///
/// [rating] stays distinct because it opens the app's existing trusted rating
/// context rather than accepting a remotely supplied route or modal contract.
enum ClientInboxActionKind { route, rating }

@immutable
class ClientInboxAction {
  const ClientInboxAction({
    required this.kind,
    required this.label,
    required this.route,
    this.extra,
  });

  final ClientInboxActionKind kind;
  final String label;
  final String route;
  final Map<String, Object?>? extra;
}

final RegExp _clientInboxUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String? _clientInboxEntityId(
  Map<String, dynamic> payload,
  List<String> keys,
) {
  for (final key in keys) {
    final value = payload[key]?.toString().trim();
    if (value != null && _clientInboxUuidPattern.hasMatch(value)) return value;
  }
  return null;
}

ClientInboxAction _clientInboxRoute(String label, String route) =>
    ClientInboxAction(
      kind: ClientInboxActionKind.route,
      label: label,
      route: route,
    );

/// Resolves one optional, locally allowlisted CTA for a Client inbox row.
///
/// Remote route fields are deliberately ignored. Dynamic paths are returned
/// only after their ids pass UUID validation; unknown events remain
/// informational and therefore return null.
ClientInboxAction? clientInboxActionFor({
  required String eventType,
  Map<String, dynamic> payload = const {},
}) {
  final type = NotificationPayload.normaliseType(
    eventType.trim().toLowerCase(),
  ).replaceAll('-', '_');

  if (type == NotificationPayload.typeAnnouncement) {
    final route = clientAnnouncementRoute(
      payload[NotificationPayload.keyDestination],
    );
    return switch (route) {
      '/activity' => _clientInboxRoute('View activity', route),
      '/profile/support' => _clientInboxRoute('Get support', route),
      '/home' => _clientInboxRoute('View promotions', route),
      _ => null,
    };
  }

  if (type == NotificationPayload.typeSupportTicketMessage ||
      type == NotificationPayload.typeSupportTicketStatusChanged) {
    final ticketId = _clientInboxEntityId(
      payload,
      const [NotificationPayload.keyTicketId, 'ticket_id'],
    );
    return ticketId == null
        ? _clientInboxRoute('View support', '/profile/support/tickets')
        : _clientInboxRoute(
            type == NotificationPayload.typeSupportTicketMessage
                ? 'View & reply'
                : 'View ticket',
            '/profile/support/tickets/$ticketId',
          );
  }

  if (type == NotificationPayload.typeRatingPrompt) {
    final bookingType = payload[NotificationPayload.keyBookingType]
        ?.toString()
        .trim()
        .toLowerCase();
    if (bookingType != 'ride' &&
        bookingType != 'job' &&
        bookingType != 'artisan_job') {
      return null;
    }
    final bookingId = _clientInboxEntityId(
      payload,
      [
        NotificationPayload.keyBookingId,
        'booking_id',
        if (bookingType == 'ride') NotificationPayload.keyRideId,
        if (bookingType != 'ride') NotificationPayload.keyJobId,
      ],
    );
    if (bookingId == null) return null;
    return ClientInboxAction(
      kind: ClientInboxActionKind.rating,
      label: 'Rate now',
      route: bookingType == 'ride'
          ? '/ride/$bookingId/receipt'
          : '/services/job/$bookingId/complete',
    );
  }

  if (type == NotificationPayload.typeNewMessage || type == 'chat_message') {
    final rawBookingType = payload[NotificationPayload.keyBookingType]
        ?.toString()
        .trim()
        .toLowerCase();
    if (rawBookingType != 'ride' &&
        rawBookingType != 'job' &&
        rawBookingType != 'artisan_job') {
      return null;
    }
    final bookingId = _clientInboxEntityId(
      payload,
      [
        NotificationPayload.keyBookingId,
        'booking_id',
        if (rawBookingType == 'ride') NotificationPayload.keyRideId,
        if (rawBookingType != 'ride') NotificationPayload.keyJobId,
      ],
    );
    if (bookingId == null) return null;
    return ClientInboxAction(
      kind: ClientInboxActionKind.route,
      label: 'View message',
      route: '/chat',
      extra: <String, Object?>{
        'bookingType': rawBookingType == 'ride' ? 'ride' : 'artisan_job',
        'bookingId': bookingId,
      },
    );
  }

  // Current persisted payment alerts carry only paymentId or disputeId. The
  // mobile router has no payment-by-id/dispute-by-id destination, and opening
  // generic Activity cannot resume an insufficient-balance retry. Keep these
  // rows informational until the backend includes authoritative booking
  // context (or a dedicated validated payment destination exists).
  if (const {
    NotificationPayload.typePaymentConfirmed,
    'payment_dispute_resolved',
    'payment_dispute_refund_approved',
    'payment_refund_processed',
    'payment_refund_delayed',
    'payment_insufficient_balance',
  }.contains(type)) {
    return null;
  }

  final rideId = _clientInboxEntityId(
    payload,
    const [
      NotificationPayload.keyRideId,
      'ride_id',
      NotificationPayload.keyBookingId,
      'booking_id',
    ],
  );
  if (const {
    NotificationPayload.typeRideDriverAssigned,
    NotificationPayload.typeRideDriverEnRoute,
    NotificationPayload.typeRideDriverArrived,
    NotificationPayload.typeRideInProgress,
    NotificationPayload.typeRideCancelled,
    'ride_provider_location_unavailable',
    'ride_provider_location_degraded_escalated',
  }.contains(type)) {
    return rideId == null
        ? null
        : _clientInboxRoute('View ride', '/activity/ride/$rideId');
  }
  if (type == NotificationPayload.typeRideCompleted || type == 'ride_settled') {
    return rideId == null
        ? null
        : _clientInboxRoute('View receipt', '/ride/$rideId/receipt');
  }

  final jobId = _clientInboxEntityId(
    payload,
    const [
      NotificationPayload.keyJobId,
      'job_id',
      NotificationPayload.keyBookingId,
      'booking_id',
    ],
  );
  if (type == NotificationPayload.typeJobSupplementRequested) {
    return jobId == null
        ? null
        : _clientInboxRoute(
            'Review supplement',
            '/services/job/$jobId/supplement',
          );
  }
  if (const {
    NotificationPayload.typeJobArtisanEnRoute,
    NotificationPayload.typeJobArtisanArrived,
    NotificationPayload.typeJobInProgress,
    NotificationPayload.typeJobMarkedComplete,
    NotificationPayload.typeJobConfirmCompletionRequested,
  }.contains(type)) {
    return jobId == null
        ? null
        : _clientInboxRoute('Open job', '/services/job/$jobId/active');
  }
  if (type == NotificationPayload.typeJobCompleted ||
      type == NotificationPayload.typeJobForceCompleted) {
    return jobId == null
        ? null
        : _clientInboxRoute('View job', '/activity/job/$jobId');
  }
  if (const {
    NotificationPayload.typeJobBidSubmitted,
    NotificationPayload.typeJobReminder2h,
    NotificationPayload.typeJobCheckin8h,
    NotificationPayload.typeJobStale24h,
    NotificationPayload.typeJobStale48h,
    NotificationPayload.typeJobNoBidsEscalated,
    NotificationPayload.typeJobArtisanNoShow,
    NotificationPayload.typeJobCancelled,
    NotificationPayload.typeJobCancelledByArtisan,
    'job_directed_quote_awaiting_accept',
    'job_directed_assignment_requeued',
    'job_provider_location_unavailable',
    'job_provider_location_degraded_escalated',
  }.contains(type)) {
    return jobId == null
        ? null
        : _clientInboxRoute('View job', '/services/job/$jobId');
  }

  return null;
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

  /// Incoming voice calls need a ringtone-class sound rather than the short
  /// notification tone used by [_urgentChannel]. Android freezes notification
  /// channel sound settings after first creation, so this uses a dedicated,
  /// versioned channel for existing installs as well as fresh ones.
  ///
  /// `content://settings/system/ringtone` is Android's stable alias for the
  /// ringtone selected by the user in device settings. The OS resolves it at
  /// playback time, so MyShop follows the device ringtone without requesting
  /// media-library access or bundling a duplicate audio file.
  static const AndroidNotificationChannel _incomingCallChannel =
      AndroidNotificationChannel(
    'myshop_incoming_calls_v1',
    'Incoming calls',
    description: 'Incoming MyShop voice calls. Uses your device ringtone.',
    importance: Importance.max,
    playSound: true,
    sound: UriAndroidNotificationSound('content://settings/system/ringtone'),
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );

  // android.app.Notification.FLAG_INSISTENT. Repeats the channel sound until
  // the notification is explicitly cancelled by accept/decline/end/timeout.
  static const int _androidFlagInsistent = 4;

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
  Future<void>? _initializing;

  /// Router-owned tap handler. Forwards the decoded payload map.
  void Function(Map<String, dynamic> payload)? _onTap;
  Map<String, dynamic>? _pendingTapPayload;

  set onTap(void Function(Map<String, dynamic> payload)? handler) {
    _onTap = handler;
    final pending = _pendingTapPayload;
    if (handler == null || pending == null) return;
    _pendingTapPayload = null;
    scheduleMicrotask(() => handler(pending));
  }

  Future<void> init() {
    if (_initialised) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    const androidInit =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosInit = DarwinInitializationSettings(
      // FcmService requests permission after the first Flutter frame. Asking
      // here made main() await an OS dialog before runApp, leaving first-run
      // users staring at the native splash until they answered it.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        _handleTapPayload(response.payload);
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _handleTapPayload(launchDetails?.notificationResponse?.payload);
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_urgentChannel);
    await androidPlugin?.createNotificationChannel(_incomingCallChannel);
    await androidPlugin?.createNotificationChannel(_timelineChannel);
    await androidPlugin?.createNotificationChannel(_chatChannel);
    _initialised = true;
  }

  /// Remove the Android incoming-call alert using the same stable id used by
  /// [showTimelineUpdate]. The deterministic hash works across background and
  /// main isolates, unlike Dart's runtime [String.hashCode] contract.
  Future<void> cancelIncomingCall(String callId) async {
    if (callId.isEmpty) return;
    await init();
    await _plugin.cancel(_incomingCallNotificationId(callId));
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
    Duration? timeoutAfter,
  }) async {
    final isUrgent = NotificationPayload.urgentTypes.contains(type);
    final isPersistentCall =
        NotificationPayload.persistentCallTypes.contains(type);
    final isChat = NotificationPayload.chatTypes.contains(type);
    final channel = isPersistentCall
        ? _incomingCallChannel
        : isUrgent
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
          // Keep calls visible, audible and actionable without forcing an
          // activity launch that Google Play disallows for this app.
          fullScreenIntent: false,
          playSound: channel.playSound,
          sound: channel.sound,
          audioAttributesUsage: channel.audioAttributesUsage,
          additionalFlags: isPersistentCall
              ? Int32List.fromList(<int>[_androidFlagInsistent])
              : null,
          autoCancel: true,
          ongoing: isPersistentCall,
          timeoutAfter:
              isPersistentCall ? _timeoutMilliseconds(timeoutAfter) : null,
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
    if (type == NotificationPayload.typeCallIncoming) {
      final callId = extras[NotificationPayload.keyCallId];
      if (callId != null && callId.isNotEmpty) {
        return _incomingCallNotificationId(callId);
      }
    }
    final primary = extras[NotificationPayload.keyRideId] ??
        extras[NotificationPayload.keyJobId] ??
        extras[NotificationPayload.keyChatId] ??
        extras[NotificationPayload.keyBidId] ??
        type;
    return ('$type:$primary').hashCode & 0x7fffffff;
  }

  int _incomingCallNotificationId(String callId) => _stableNotificationId(
        '${NotificationPayload.typeCallIncoming}:$callId',
      );

  int _stableNotificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  int? _timeoutMilliseconds(Duration? timeout) {
    if (timeout == null) return null;
    return timeout.inMilliseconds < 1 ? 1 : timeout.inMilliseconds;
  }

  void _handleTapPayload(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);
      final handler = _onTap;
      if (handler == null) {
        _pendingTapPayload = payload;
      } else {
        handler(payload);
      }
    } catch (e) {
      debugPrint('[LocalNotificationService] bad payload: $e');
    }
  }
}

/// Exposed so widgets can `ref.read(...).playForegroundAlert()` or access
/// the singleton directly.
final localNotificationServiceProvider =
    Provider<LocalNotificationService>((_) {
  return LocalNotificationService.instance;
});
