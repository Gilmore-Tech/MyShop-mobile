import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keys + type constants embedded in local/FCM notification payloads. The
/// backend must send the SAME [keyType] string in `data` so the tap handler
/// can deep-link into the correct screen.
///
/// Keep in sync with [client app: local_notification_service.dart] and the
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
  /// (e.g. `ride.driver_assigned`, `job.bid_accepted`, `chat.message`).
  /// Normalise them to the underscore form used by the [type*] constants
  /// so the switch doesn't care which separator the emitter picked.
  static String normaliseType(String raw) => raw.replaceAll('.', '_');

  // ── Incoming requests (provider-targeted) ────────────────────────────────
  /// New artisan job request that the provider qualifies for.
  static const typeJobRequest = 'job_request';

  /// New ride request that the driver qualifies for.
  static const typeRideRequest = 'ride_request';

  // ── Job progression (provider-targeted) ──────────────────────────────────
  /// Client accepted the artisan's bid — urgent, artisan can now start.
  static const typeBidAccepted = 'bid_accepted';

  /// Client rejected the artisan's bid.
  static const typeBidRejected = 'bid_rejected';

  /// Client cancelled an accepted job after work had started — generic.
  /// Backend may also emit the more specific [typeJobCancelledByClient].
  static const typeJobCancelled = 'job_cancelled';

  /// Specific variant of [typeJobCancelled] when the backend wants to
  /// attribute the cancellation in copy.
  static const typeJobCancelledByClient = 'job_cancelled_by_client';

  /// Client confirmed the artisan's "marked complete" — payment released.
  static const typeJobConfirmedComplete = 'job_confirmed_complete';

  /// Backend has flagged this job as ready for payout — funds being
  /// released to the artisan's wallet.
  static const typeJobPaymentReleasing = 'job_payment_releasing';

  /// Admin manually assigned this artisan to a job (urgent — needs
  /// review and bid).
  static const typeJobManuallyAssigned = 'job_manually_assigned';

  /// 24-hour pre-job reminder (informational).
  static const typeJobReminder24h = 'job_reminder_24h';

  /// 2-hour pre-job reminder (urgent — leave for the site).
  static const typeJobReminder2h = 'job_reminder_2h';

  /// 8-hour mid-job check-in nudge.
  static const typeJobCheckin8h = 'job_checkin_8h';

  /// 24-hour staleness reminder (no progress recorded).
  static const typeJobStale24h = 'job_stale_24h';

  /// 48-hour staleness escalation (auto-cancellation imminent).
  static const typeJobStale48h = 'job_stale_48h';

  /// Backend welfare-check ping (long-running job).
  static const typeJobWelfareCheck = 'job_welfare_check';

  /// No bids on a job after the matching window — admin re-routed it
  /// for manual assignment, this artisan is being given a chance to bid.
  static const typeJobNoBidsEscalated = 'job_no_bids_escalated';

  /// Client approved the artisan's supplement request.
  static const typeSupplementApproved = 'supplement_approved';

  /// Client rejected the artisan's supplement request.
  static const typeSupplementRejected = 'supplement_rejected';

  // ── Ride progression (provider-targeted) ─────────────────────────────────
  /// Client cancelled the ride after matching.
  static const typeRideCancelled = 'ride_cancelled';

  /// Client confirmed the ride complete — fare settled.
  static const typeRideSettled = 'ride_settled';

  // ── Cross-cutting ────────────────────────────────────────────────────────
  /// New chat message from the client.
  static const typeNewMessage = 'new_message';

  /// Payout / payment received from MyShop.
  static const typePaymentReceived = 'payment_received';

  /// Backend asks the provider to rate the counter-party for a completed
  /// booking. Payload carries `bookingType` (`ride` | `artisan_job`) and
  /// `bookingId`. Tapping deep-links to the matching rating sheet.
  static const typeRatingPrompt = 'rating_prompt';

  /// Generic / info — routes to notification inbox.
  static const typeGeneric = 'generic';

  // ── Support tickets ──────────────────────────────────────────────────────
  /// New message from a support agent on an open ticket.
  static const typeSupportTicketMessage = 'support_ticket_message';

  /// Ticket status flipped server-side (resolved by agent, etc.).
  static const typeSupportTicketStatusChanged = 'support_ticket_status_changed';

  /// Payload key for support deeplinks.
  static const keyTicketId = 'ticketId';
  static const keyMessageId = 'messageId';

  /// Types that must fire a full-screen-intent, heads-up, call-style banner.
  /// Incoming requests MUST be in this set so the provider sees them on the
  /// lock-screen even when the phone is in a pocket.
  static const Set<String> urgentTypes = {
    typeJobRequest,
    typeRideRequest,
    typeBidAccepted,
    typeJobReminder2h,
    typeJobManuallyAssigned,
  };

  /// Subset of [urgentTypes] that get the call-style "incoming request"
  /// treatment when delivered to a backgrounded Android app: full-screen
  /// intent, sticky (`ongoing: true`), and a 30-second `setTimeoutAfter`
  /// so the OS auto-dismisses the banner if the provider doesn't act.
  /// Backend pairs this with an Android-data-only push so FCM's auto
  /// banner doesn't fire on top of our local notification (see
  /// `apps/api/src/modules/notification/push.service.ts FULL_SCREEN_DATA_TYPES`).
  static const Set<String> fullScreenRequestTypes = {
    typeJobRequest,
    typeRideRequest,
  };

  /// Auto-dismiss window for the Android full-screen banner.
  ///
  /// Ride requests are only actionable for the backend matcher window
  /// (`ride_driver_acceptance_window_secs`, currently 30 s). Keeping the
  /// OS notification alive beyond that creates a dead-tap window where the
  /// driver can open an already-expired request and land on the unavailable
  /// fallback screen.
  static const Duration fullScreenRequestTimeout = Duration(seconds: 30);

  /// Types that should render through the dedicated `chat_messages` channel
  /// (Android) / `MESSAGE` category (iOS) so the OS treats them like
  /// conversational pings — time-sensitive but not call-style.
  static const Set<String> chatTypes = {typeNewMessage};
}

/// Wraps `flutter_local_notifications` for the provider app. Responsibilities:
///   • Register two notification channels on init.
///   • Render FCM pushes that arrive while the app is backgrounded or
///     terminated (FCM's default banner has no payload tap routing).
///   • Forward taps to whatever the router has registered via [onTap].
///
/// All payloads share the shape `{type, jobId | rideId | bidId | chatId}`
/// so a single tap handler can deep-link regardless of the notification
/// type.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Max importance — full-screen-intent call-style banner. Used for the
  /// non-incoming-request urgent set (bid accepted, 2-hour reminder,
  /// admin assignment). Channel id is kept as `job_alerts` for
  /// backward-compat with the existing Android install base — Android
  /// channel sound is locked at creation time and can't be safely
  /// retuned for users who already installed the app.
  static const AndroidNotificationChannel _urgentChannel =
      AndroidNotificationChannel(
    'job_alerts',
    'Job & Ride Requests',
    description: 'Time-sensitive alerts (bid accepted, job assigned, 2-hour '
        'reminders). Muting this channel will cause you to miss work.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Dedicated channel for new incoming job/ride requests. Separate from
  /// [_urgentChannel] so a long ringtone on this channel doesn't bleed
  /// into bid-accepted / reminder pings — Android locks channel sound
  /// at creation time, so the only way to give one type of urgent a
  /// different sound is its own channel id.
  ///
  /// Channel id uses a v2 suffix because Android freezes channel sound and
  /// importance after first creation. Upgrading the id gives already-installed
  /// providers the intended request ringtone/sticky behavior instead of
  /// inheriting old channel settings.
  ///
  /// Sound resource: `res/raw/incoming_request.mp3` (or `.ogg`/`.wav`).
  /// See `res/raw/README.md` for the file the app expects. If the
  /// resource is missing, Android silently falls back to the default
  /// notification sound — the channel still rings, just not with the
  /// custom ringtone.
  static const AndroidNotificationChannel _incomingRequestChannel =
      AndroidNotificationChannel(
    'incoming_requests_v2',
    'Incoming Job & Ride Requests',
    description:
        'New job and ride request alerts. Plays the MyShop ringtone for up '
        'to 30 seconds so you can hear it across the room.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('incoming_request'),
    enableVibration: true,
  );

  /// High importance but non-intrusive — incremental updates like a
  /// cancelled ride or a received payout. Tappable, no full-screen-intent.
  static const AndroidNotificationChannel _timelineChannel =
      AndroidNotificationChannel(
    'myshop_timeline',
    'Job & ride updates',
    description:
        'Progress updates on your active jobs, rides, payouts and bids.',
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
    description:
        'New messages from drivers, artisans, riders and clients during '
        'your active bookings.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  bool _initialised = false;
  Future<void>? _initializing;

  void Function(Map<String, dynamic> payload)? _onTap;
  set onTap(void Function(Map<String, dynamic> payload)? handler) =>
      _onTap = handler;

  Future<void> init() {
    if (_initialised) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosInit = DarwinInitializationSettings(
      // Permission belongs to FcmService after the first Flutter frame.
      // Keeping it out of channel initialization prevents an OS dialog from
      // holding main() on the native splash.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
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
    await androidPlugin?.createNotificationChannel(_incomingRequestChannel);
    await androidPlugin?.createNotificationChannel(_timelineChannel);
    await androidPlugin?.createNotificationChannel(_chatChannel);
    _initialised = true;
  }

  /// Show a persistent banner for an incoming job. Used by FCM background
  /// handler when the app is minimised — tapping takes the user back into
  /// the full job-request screen via [onTap].
  Future<void> showJobRequest({
    required String jobId,
    required String title,
    required String body,
  }) {
    return showTimelineUpdate(
      type: NotificationPayload.typeJobRequest,
      title: title,
      body: body,
      extras: {NotificationPayload.keyJobId: jobId},
    );
  }

  /// Same as [showJobRequest] but for incoming ride events.
  Future<void> showRideRequest({
    required String rideId,
    required String title,
    required String body,
  }) {
    return showTimelineUpdate(
      type: NotificationPayload.typeRideRequest,
      title: title,
      body: body,
      extras: {NotificationPayload.keyRideId: rideId},
    );
  }

  /// Single entry-point for rendering any timeline push. Picks the right
  /// channel + styling based on [type]. Urgent types get a full-screen
  /// intent call-style banner; others get a standard high-priority banner.
  ///
  /// [type] MUST be one of [NotificationPayload]'s `type*` constants.
  /// [extras] is merged into the payload — pass ids like
  /// `{jobId: '...'}` or `{rideId: '...'}` so the tap handler can route.
  Future<void> showTimelineUpdate({
    required String type,
    required String title,
    required String body,
    Map<String, String> extras = const {},
  }) async {
    final isUrgent = NotificationPayload.urgentTypes.contains(type);
    final isChat = NotificationPayload.chatTypes.contains(type);
    final isFullScreenRequest =
        NotificationPayload.fullScreenRequestTypes.contains(type);
    // Order matters: the incoming-request channel is the "most specific"
    // urgent path (custom ringtone, sticky, 30 s timeout). Falling back
    // to _urgentChannel for the rest of the urgent set keeps bid_accepted
    // / reminder pings on the original sound profile users have already
    // tuned.
    final channel = isFullScreenRequest
        ? _incomingRequestChannel
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
          // Full-screen intent is intentionally OFF. The USE_FULL_SCREEN_INTENT
          // permission is stripped from the merged manifest (Google Play only
          // auto-grants it to alarm / calling apps on Android 14+, and a
          // provider app doesn't qualify — see AndroidManifest.xml). Without
          // the permission the OS ignores this flag anyway, so we set it false
          // explicitly to keep code and manifest honest. Urgent requests still
          // alert loudly via the max-importance heads-up banner, custom
          // ringtone, vibration and WAKE_LOCK above.
          fullScreenIntent: false,
          // Tap dismisses for every type (it's the standard notification
          // behavior). Incoming-request types additionally stick
          // (`ongoing: true`) so the user can't accidentally swipe the
          // call-style banner away mid-pocket; the OS clears it via
          // `timeoutAfter` after the 30 s window OR when the user taps.
          autoCancel: true,
          ongoing: isFullScreenRequest,
          timeoutAfter: isFullScreenRequest
              ? NotificationPayload.fullScreenRequestTimeout.inMilliseconds
              : null,
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
      payload: json.encode({NotificationPayload.keyType: type, ...extras}),
    );
  }

  /// Play the system alert sound and fire heavy haptic — used while the
  /// app is in the foreground and the modal is already visible (no banner
  /// needed since the UI is already grabbing attention).
  ///
  /// Fires the haptic twice and the sound once; effective on iOS + Android
  /// without needing a custom asset.
  Future<void> playForegroundAlert() async {
    await HapticFeedback.heavyImpact();
    await SystemSound.play(SystemSoundType.alert);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await HapticFeedback.heavyImpact();
  }

  // ── Incoming-request ringtone ──────────────────────────────────────────
  // Loops `assets/audio/incoming_request.mp3` via [AudioPlayer] for the
  // duration of the foreground job/ride modal. A heavy haptic also
  // pulses every 1.5 s so a phone in a pocket gets felt even when audio
  // routes to a low-volume sink (Bluetooth headset, silent mode, etc.).
  //
  // If the asset is missing — the placeholder file isn't dropped yet —
  // the player throws on `play()` and we silently fall back to
  // haptic-only. See `assets/audio/README.md` for the file the app
  // expects.
  AudioPlayer? _ringtonePlayer;
  Timer? _ringtoneTimer;
  bool _ringtoneActive = false;

  /// Start a continuous "incoming request" ringtone. Idempotent — a second
  /// call while the ringtone is already playing is a no-op. Used by the
  /// foreground job/ride request modal/screen to alert the provider.
  Future<void> startIncomingRingtone() async {
    if (_ringtoneActive) return;
    _ringtoneActive = true;

    // Haptic loop fires regardless of audio outcome — it's the
    // single signal we know works on every device the asset path
    // doesn't (Samsung silent mode, missing asset, etc.).
    await HapticFeedback.heavyImpact();
    _ringtoneTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.heavyImpact();
    });

    // Audio loop is best-effort. Until the MP3 is dropped into
    // assets/audio/, AssetSource throws and we end up haptic-only.
    try {
      final player = _ringtonePlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      // Notification stream so the OS volume keys / silent switch
      // behave the way users expect for a ringtone-class alert.
      // (audioplayers picks a sensible default if this fails on iOS.)
      try {
        await player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notificationRingtone,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {
                AVAudioSessionOptions.mixWithOthers,
                AVAudioSessionOptions.duckOthers,
              },
            ),
          ),
        );
      } catch (e) {
        debugPrint('[LocalNotificationService] audio context setup failed: $e');
      }
      await player.play(AssetSource('audio/incoming_request.mp3'));
      debugPrint('[LocalNotificationService] ringtone playing');
    } catch (e) {
      debugPrint(
        '[LocalNotificationService] ringtone asset unavailable, '
        'falling back to haptic-only: $e',
      );
    }
  }

  /// Stop the incoming-request ringtone. Safe to call when nothing is
  /// playing. Always called from `dispose` of the corresponding screen
  /// so dismissing/accepting/declining/timing-out all silence the alert.
  Future<void> stopIncomingRingtone() async {
    if (!_ringtoneActive) return;
    _ringtoneActive = false;
    _ringtoneTimer?.cancel();
    _ringtoneTimer = null;
    try {
      await _ringtonePlayer?.stop();
    } catch (e) {
      debugPrint('[LocalNotificationService] ringtone stop failed: $e');
    }
  }

  /// Stable non-negative notification id. Dedupes per `{type, primary-id}`
  /// so a status progression REPLACES the previous banner rather than
  /// stacking four notifications for the same job.
  int _dedupeId(String type, Map<String, String> extras) {
    final primary = extras[NotificationPayload.keyJobId] ??
        extras[NotificationPayload.keyRideId] ??
        extras[NotificationPayload.keyBidId] ??
        extras[NotificationPayload.keyChatId] ??
        type;
    return ('$type:$primary').hashCode & 0x7fffffff;
  }
}

final notificationServiceProvider = Provider<LocalNotificationService>((_) {
  return LocalNotificationService.instance;
});
