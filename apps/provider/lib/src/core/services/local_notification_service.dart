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
  static const keyCallId = 'callId';
  static const keyExpiresAt = 'expiresAt';
  static const keyOfferId = 'offerId';
  static const keyActionId = 'actionId';

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

  /// Client confirmed the artisan's "marked complete" state. This event is
  /// not provider-payout authority.
  static const typeJobConfirmedComplete = 'job_confirmed_complete';

  /// Backend has flagged this job for settlement processing. The notification
  /// must not claim wallet transfer without authoritative payout status.
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

  /// Post-commit balance revision. Payload amounts are never trusted; receipt
  /// only triggers an authoritative earnings-summary refresh.
  static const typeEarningsUpdated = 'earnings_updated';

  /// Backend asks the provider to rate the counter-party for a completed
  /// booking. Payload carries `bookingType` (`ride` | `artisan_job`) and
  /// `bookingId`. Tapping deep-links to the matching rating sheet.
  static const typeRatingPrompt = 'rating_prompt';

  /// Generic / info — routes to notification inbox.
  static const typeGeneric = 'generic';

  // Provider-document lifecycle alerts. These route to the corrective
  // Documents & Verification screen instead of silently falling back Home.
  static const typeProviderDocumentUploadConfirmed =
      'provider_document_upload_confirmed';
  static const typeProviderDocumentExpiryNotice =
      'provider_document_expiry_notice';
  static const typeProviderDocumentExpiry72h = 'provider_document_expiry_72h';
  static const typeProviderDocumentExpiry24h = 'provider_document_expiry_24h';
  static const typeProviderDocumentExpiry2h = 'provider_document_expiry_2h';
  static const typeProviderDocumentExpired = 'provider_document_expired';
  static const typeProviderDocumentReplacementGraceStarted =
      'provider_document_replacement_grace_started';
  static const typeProviderDocumentReplacementGraceExpired =
      'provider_document_replacement_grace_expired';

  // Manual verification decisions. These are emitted without the `provider.`
  // prefix by the review service and must still land on the same corrective
  // document screen.
  static const typeVerificationApproved = 'verification_approved';
  static const typeVerificationRejected = 'verification_rejected';
  static const typeVerificationDocumentReviewed =
      'verification_document_reviewed';
  static const typeVerificationDocumentApproved =
      'verification_document_approved';
  static const typeVerificationDocumentRejected =
      'verification_document_rejected';

  /// Per-vehicle ride category decisions. The destination is derived locally;
  /// a remote `route` value is never trusted for these events.
  static const typeRideCategoryApproved = 'ride_category_approved';
  static const typeRideCategoryRejected = 'ride_category_rejected';

  /// In-app voice call fallback. iOS should route this through CallKit when
  /// Flutter receives it; background/locked iOS must still rely on PushKit.
  static const typeCallIncoming = 'call_incoming';

  /// Control-only push used to dismiss an unanswered incoming call after the
  /// caller hangs up. It must never render its own notification.
  static const typeCallEnded = 'call_ended';

  /// Silent control message that removes a ride/job offer which is no longer
  /// actionable (accepted elsewhere, cancelled, skipped, or expired).
  static const typeOfferRevoked = 'offer_revoked';

  // Native/local-notification request action identifiers. Keep these in sync
  // with provider iOS AppDelegate and the incoming_request_overlay plugin.
  static const actionRideAccept = 'RIDE_ACCEPT';
  static const actionRideSkip = 'RIDE_SKIP';
  static const actionRideView = 'RIDE_VIEW';
  static const actionJobSubmitBid = 'JOB_SUBMIT_BID';
  static const actionJobSkip = 'JOB_SKIP';
  static const actionJobView = 'JOB_VIEW';

  // ── Support tickets ──────────────────────────────────────────────────────
  /// New message from a support agent on an open ticket.
  static const typeSupportTicketMessage = 'support_ticket_message';

  /// Ticket status flipped server-side (resolved by agent, etc.).
  static const typeSupportTicketStatusChanged = 'support_ticket_status_changed';

  /// Payload key for support deeplinks.
  static const keyTicketId = 'ticketId';
  static const keyMessageId = 'messageId';

  /// Time-sensitive types. Ride/job requests use the custom native overlay
  /// (or this service's sticky, actionable heads-up fallback when overlay
  /// access is unavailable). Voice calls use a persistent call-category
  /// notification; Google Play does not permit this marketplace app to force
  /// a full-screen activity launch.
  static const Set<String> urgentTypes = {
    typeCallIncoming,
    typeJobRequest,
    typeRideRequest,
    typeBidAccepted,
    typeJobReminder2h,
    typeJobManuallyAssigned,
  };

  /// Subset of [urgentTypes] that get the persistent incoming-alert treatment
  /// when delivered to a backgrounded Android app: a dedicated channel,
  /// repeating sound, `ongoing: true`, and an exact `setTimeoutAfter`.
  /// Backend pairs this with an Android-data-only push so FCM's auto
  /// banner doesn't fire on top of our local notification (see
  /// `apps/api/src/modules/notification/push.service.ts FULL_SCREEN_DATA_TYPES`).
  static const Set<String> persistentRequestTypes = {
    typeCallIncoming,
    typeJobRequest,
    typeRideRequest,
  };

  /// Legacy auto-dismiss fallback when a backend request has no `expiresAt`.
  ///
  /// Job offers retain the legacy 45-second fallback. Ride offers use the
  /// receipt-based deadline and the dedicated 30-second fallback below.
  static const Duration persistentRequestTimeout = Duration(seconds: 45);
  static const Duration rideRequestTimeout = Duration(seconds: 30);

  /// Types that should render through the dedicated `chat_messages` channel
  /// (Android) / `MESSAGE` category (iOS) so the OS treats them like
  /// conversational pings — time-sensitive but not call-style.
  static const Set<String> chatTypes = {typeNewMessage};
}

/// Returns the only corrective destination accepted for provider-document
/// lifecycle notifications. Routing is derived from a known event type rather
/// than an arbitrary server-supplied path.
String? providerDocumentLifecycleRoute(String rawType) {
  return switch (NotificationPayload.normaliseType(rawType)) {
    NotificationPayload.typeProviderDocumentUploadConfirmed ||
    NotificationPayload.typeProviderDocumentExpiryNotice ||
    NotificationPayload.typeProviderDocumentExpiry72h ||
    NotificationPayload.typeProviderDocumentExpiry24h ||
    NotificationPayload.typeProviderDocumentExpiry2h ||
    NotificationPayload.typeProviderDocumentExpired ||
    NotificationPayload.typeProviderDocumentReplacementGraceStarted ||
    NotificationPayload.typeProviderDocumentReplacementGraceExpired ||
    NotificationPayload.typeVerificationApproved ||
    NotificationPayload.typeVerificationRejected ||
    NotificationPayload.typeVerificationDocumentReviewed ||
    NotificationPayload.typeVerificationDocumentApproved ||
    NotificationPayload.typeVerificationDocumentRejected =>
      '/account/documents',
    _ => null,
  };
}

/// Returns a locally allowlisted destination for provider vehicle/category and
/// document lifecycle events. Unknown types return null even if their payload
/// contains a route-like string.
String? providerLifecycleNotificationRoute(String rawType) {
  final normalized = NotificationPayload.normaliseType(rawType);
  final documentRoute = providerDocumentLifecycleRoute(normalized);
  if (documentRoute != null) return documentRoute;
  return switch (normalized) {
    NotificationPayload.typeRideCategoryApproved ||
    NotificationPayload.typeRideCategoryRejected =>
      '/account/vehicle',
    _ => null,
  };
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

  /// Dedicated voice-call channel using the ringtone selected in Android
  /// device settings. Calls must not share [_incomingRequestChannel]: that
  /// channel is for job/ride offers and points at an optional MyShop asset.
  /// Android freezes channel sound settings after first creation, hence the
  /// versioned id also repairs already-installed builds.
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

  // android.app.Notification.FLAG_INSISTENT. Repeats the ringtone until the
  // call notification is explicitly cancelled.
  static const int _androidFlagInsistent = 4;

  /// Dedicated channel for new incoming job/ride requests. Separate from
  /// [_urgentChannel] so a long ringtone on this channel doesn't bleed
  /// into bid-accepted / reminder pings — Android locks channel sound
  /// at creation time, so the only way to give one type of urgent a
  /// different sound is its own channel id.
  ///
  /// Channel id uses a v3 suffix because Android freezes channel sound and
  /// importance after first creation. Upgrading the id gives already-installed
  /// providers the intended request ringtone/sticky behavior instead of
  /// inheriting the previous packaged tone from v2.
  ///
  /// Sound resource: `res/raw/incoming_request.mp3`.
  static const AndroidNotificationChannel _incomingRequestChannel =
      AndroidNotificationChannel(
    'incoming_requests_v3',
    'Incoming Job & Ride Requests',
    description:
        'New job and ride request alerts. Plays the MyShop ringtone until '
        'the request decision deadline.',
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
        _handleTapPayload(
          response.payload,
          actionId: response.actionId,
        );
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails?.notificationResponse;
      _handleTapPayload(response?.payload, actionId: response?.actionId);
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_urgentChannel);
    await androidPlugin?.createNotificationChannel(_incomingCallChannel);
    await androidPlugin?.createNotificationChannel(_incomingRequestChannel);
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

  /// Remove a job/ride fallback notification using the same deterministic id
  /// used by [showTimelineUpdate]. Safe across main/background isolates.
  Future<void> cancelIncomingRequest({
    required String type,
    required String requestId,
  }) async {
    if (requestId.isEmpty) return;
    if (type != NotificationPayload.typeRideRequest &&
        type != NotificationPayload.typeJobRequest) {
      return;
    }
    await init();
    final key = type == NotificationPayload.typeRideRequest
        ? NotificationPayload.keyRideId
        : NotificationPayload.keyJobId;
    await _plugin.cancel(_dedupeId(type, {key: requestId}));
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
  /// channel + styling based on [type]. Incoming calls and ride/job requests
  /// remain persistent and actionable without forcing a full-screen launch.
  ///
  /// [type] MUST be one of [NotificationPayload]'s `type*` constants.
  /// [extras] is merged into the payload — pass ids like
  /// `{jobId: '...'}` or `{rideId: '...'}` so the tap handler can route.
  Future<void> showTimelineUpdate({
    required String type,
    required String title,
    required String body,
    Map<String, String> extras = const {},
    Duration? timeoutAfter,
  }) async {
    final isUrgent = NotificationPayload.urgentTypes.contains(type);
    final isChat = NotificationPayload.chatTypes.contains(type);
    final isPersistentRequest =
        NotificationPayload.persistentRequestTypes.contains(type);
    // Order matters: the incoming-request channel is the "most specific"
    // urgent path (custom ringtone, sticky, server-authoritative timeout). Falling back
    // to _urgentChannel for the rest of the urgent set keeps bid_accepted
    // / reminder pings on the original sound profile users have already
    // tuned.
    final isIncomingCall = type == NotificationPayload.typeCallIncoming;
    final channel = isIncomingCall
        ? _incomingCallChannel
        : isPersistentRequest
            ? _incomingRequestChannel
            : isUrgent
                ? _urgentChannel
                : isChat
                    ? _chatChannel
                    : _timelineChannel;

    final androidCategory = isIncomingCall
        ? AndroidNotificationCategory.call
        : isPersistentRequest
            ? AndroidNotificationCategory.transport
            : isChat
                ? AndroidNotificationCategory.message
                : AndroidNotificationCategory.status;

    final androidActions = switch (type) {
      NotificationPayload.typeRideRequest => const <AndroidNotificationAction>[
          AndroidNotificationAction(
            NotificationPayload.actionRideAccept,
            'Accept',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            NotificationPayload.actionRideSkip,
            'Skip',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            NotificationPayload.actionRideView,
            'View details',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      NotificationPayload.typeJobRequest => const <AndroidNotificationAction>[
          AndroidNotificationAction(
            NotificationPayload.actionJobSubmitBid,
            'Submit bid',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            NotificationPayload.actionJobSkip,
            'Skip',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            NotificationPayload.actionJobView,
            'View job',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      _ => const <AndroidNotificationAction>[],
    };

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
          // Google Play rejected forced full-screen takeover for this app.
          // Persistence is provided by the call/request channel, ongoing
          // notification and (for ride/jobs) the native overlay service.
          fullScreenIntent: false,
          playSound: channel.playSound,
          sound: channel.sound,
          audioAttributesUsage: channel.audioAttributesUsage,
          additionalFlags: isPersistentRequest
              ? Int32List.fromList(<int>[_androidFlagInsistent])
              : null,
          actions: androidActions,
          // Tap dismisses for every type (it's the standard notification
          // behavior). Incoming-request types additionally stick
          // (`ongoing: true`) so the user can't accidentally swipe the
          // call-style banner away mid-pocket; the OS clears it via
          // `timeoutAfter` at the request deadline OR when the user taps.
          autoCancel: true,
          ongoing: isPersistentRequest,
          timeoutAfter: isPersistentRequest
              ? _timeoutMilliseconds(
                  timeoutAfter ??
                      (type == NotificationPayload.typeRideRequest
                          ? NotificationPayload.rideRequestTimeout
                          : NotificationPayload.persistentRequestTimeout),
                )
              : null,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: isPersistentRequest ? 'incoming_request.caf' : null,
          // Pair the iOS category with the appropriate interruption tier:
          //   urgent  → time-sensitive (cuts through Focus modes)
          //   chat    → time-sensitive + MESSAGE (iOS treats it like SMS)
          //   default → active
          categoryIdentifier: switch (type) {
            NotificationPayload.typeRideRequest => 'RIDE_REQUEST',
            NotificationPayload.typeJobRequest => 'JOB_REQUEST',
            _ => isChat ? 'MESSAGE' : null,
          },
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
  // Audio remains best-effort: if decoding or routing fails, the haptic loop
  // still alerts the provider.
  AudioPlayer? _ringtonePlayer;
  Timer? _ringtoneTimer;
  bool _ringtoneActive = false;
  int _ringtoneGeneration = 0;

  bool _isCurrentRingtoneSession(int generation) =>
      _ringtoneActive && _ringtoneGeneration == generation;

  /// Start a continuous "incoming request" ringtone. Idempotent — a second
  /// call while the ringtone is already playing is a no-op. Used by the
  /// foreground job/ride request modal/screen to alert the provider.
  Future<void> startIncomingRingtone() async {
    if (_ringtoneActive) return;
    _ringtoneActive = true;
    final generation = ++_ringtoneGeneration;

    // Haptic loop fires regardless of audio outcome — it's the
    // single signal we know works on every device the asset path
    // doesn't (Samsung silent mode, missing asset, etc.).
    await HapticFeedback.heavyImpact();
    if (!_isCurrentRingtoneSession(generation)) return;
    _ringtoneTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_isCurrentRingtoneSession(generation)) {
        HapticFeedback.heavyImpact();
      }
    });

    // Audio loop is best-effort; decoder/audio-route failures fall back to
    // the haptic loop above.
    try {
      final player = _ringtonePlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      if (!_isCurrentRingtoneSession(generation)) return;
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
      if (!_isCurrentRingtoneSession(generation)) return;
      await player.play(AssetSource('audio/incoming_request.mp3'));
      // The request may have been accepted/dismissed while the native player
      // was still preparing. Stop again after the await so an old start can
      // never resurrect the ringtone after its request surface has closed.
      if (!_isCurrentRingtoneSession(generation)) {
        await player.stop();
        return;
      }
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
    _ringtoneGeneration++;
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
    if (type == NotificationPayload.typeCallIncoming) {
      final callId = extras[NotificationPayload.keyCallId];
      if (callId != null && callId.isNotEmpty) {
        return _incomingCallNotificationId(callId);
      }
    }
    final primary = extras[NotificationPayload.keyJobId] ??
        extras[NotificationPayload.keyRideId] ??
        extras[NotificationPayload.keyBidId] ??
        extras[NotificationPayload.keyChatId] ??
        type;
    return _stableNotificationId('$type:$primary');
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

  void _handleTapPayload(String? raw, {String? actionId}) {
    final payload = decodeNotificationTapPayload(raw, actionId: actionId);
    if (payload == null) return;
    final handler = _onTap;
    if (handler == null) {
      _pendingTapPayload = payload;
    } else {
      handler(payload);
    }
  }
}

@visibleForTesting
Map<String, dynamic>? decodeNotificationTapPayload(
  String? raw, {
  String? actionId,
}) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = json.decode(raw);
    if (decoded is! Map) return null;
    final payload = Map<String, dynamic>.from(decoded);
    if (actionId != null && actionId.isNotEmpty) {
      payload[NotificationPayload.keyActionId] = actionId;
    }
    return payload;
  } catch (e) {
    debugPrint('[LocalNotificationService] bad payload: $e');
    return null;
  }
}

final notificationServiceProvider = Provider<LocalNotificationService>((_) {
  return LocalNotificationService.instance;
});
