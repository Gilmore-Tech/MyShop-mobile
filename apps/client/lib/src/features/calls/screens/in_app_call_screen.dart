import 'dart:async';
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/services/local_notification_service.dart';

class ClientInAppCallScreen extends ConsumerStatefulWidget {
  const ClientInAppCallScreen({
    super.key,
    required this.callId,
    this.initialSession,
  });

  final String callId;
  final AppCallSession? initialSession;

  @override
  ConsumerState<ClientInAppCallScreen> createState() =>
      _ClientInAppCallScreenState();
}

class _ClientInAppCallScreenState extends ConsumerState<ClientInAppCallScreen> {
  AppCallSession? _session;
  bool _loading = true;
  bool _ending = false;
  bool _accepting = false;
  bool _declining = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _retryingRtc = false;
  String? _errorMessage;
  StreamSubscription<AppCallSession>? _callStateSub;
  StreamSubscription<AppCallRtcConnectionState>? _rtcStateSub;
  Timer? _refreshTimer;
  Timer? _terminalCloseTimer;
  AppCallRtcService? _rtc;
  AppCallRtcConnectionState _rtcState = AppCallRtcConnectionState.disconnected;
  bool _rtcStarting = false;
  Future<void>? _acceptedTransition;
  Future<AppCallSession>? _sessionRequest;
  int _sessionMutationEpoch = 0;
  int _rtcAttempt = 0;
  final CallRingbackPlayer _ringback = CallRingbackPlayer();

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _loading = _session == null;
    _listenForCallState();
    _joinCall();
  }

  @override
  void dispose() {
    _rtcAttempt += 1;
    _terminalCloseTimer?.cancel();
    _refreshTimer?.cancel();
    _callStateSub?.cancel();
    _rtcStateSub?.cancel();
    unawaited(_ringback.stop());
    unawaited(_rtc?.dispose());
    final socket = ref.read(appCallSocketServiceProvider);
    socket.leaveCall(widget.callId);
    socket.disconnect();
    super.dispose();
  }

  void _listenForCallState() {
    final socket = ref.read(appCallSocketServiceProvider);
    _callStateSub = socket.sessionStream.listen(_applyRemoteSession);
    unawaited(socket.joinCall(widget.callId));
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshCallState()),
    );
  }

  Future<void> _joinCall() async {
    final epoch = _sessionMutationEpoch;
    try {
      final session = await _loadSession();
      if (!mounted || epoch != _sessionMutationEpoch) return;
      _applyRemoteSession(session);
    } catch (error) {
      if (!mounted || epoch != _sessionMutationEpoch) return;
      setState(() {
        _loading = false;
        _errorMessage = _callErrorMessage(error);
      });
    }
  }

  Future<void> _refreshCallState() async {
    if (!mounted ||
        _session?.isTerminal == true ||
        _ending ||
        _accepting ||
        _declining) {
      return;
    }
    final epoch = _sessionMutationEpoch;
    try {
      final session = await _loadSession();
      if (!mounted || epoch != _sessionMutationEpoch) return;
      _applyRemoteSession(session);
    } catch (_) {
      // Best-effort fallback only; the visible error state belongs to the
      // initial join/end actions, not a background refresh tick.
    }
  }

  Future<AppCallSession> _loadSession() {
    final existing = _sessionRequest;
    if (existing != null) return existing;

    late final Future<AppCallSession> operation;
    operation = ref
        .read(appCallServiceProvider)
        .joinCall(widget.callId)
        .whenComplete(() {
      if (identical(_sessionRequest, operation)) _sessionRequest = null;
    });
    _sessionRequest = operation;
    return operation;
  }

  void _invalidateSessionRequest() {
    _sessionMutationEpoch += 1;
    // A Future cannot be cancelled, but detaching it prevents a later refresh
    // from reusing a pre-mutation response. Its epoch check still prevents the
    // original waiter from applying that stale response.
    _sessionRequest = null;
  }

  void _applyRemoteSession(AppCallSession session) {
    if (!mounted || session.callId != widget.callId) return;
    final current = _session;
    // REST polling and socket broadcasts race each other. Call lifecycle state
    // is monotonic, so never let a slower, older response move an accepted or
    // terminal call back to ringing (or resurrect a terminal call).
    if ((current?.isAccepted == true && session.isRinging) ||
        (current?.isTerminal == true && !session.isTerminal)) {
      return;
    }
    setState(() {
      _session = session;
      _loading = false;
      if (_rtcState != AppCallRtcConnectionState.failed &&
          !(_rtc != null &&
              _rtcState == AppCallRtcConnectionState.disconnected)) {
        _errorMessage = null;
      }
    });
    if (session.isTerminal) {
      unawaited(_ringback.stop());
      unawaited(
        LocalNotificationService.instance.cancelIncomingCall(widget.callId),
      );
      _scheduleTerminalClose(session);
    } else if (session.status == 'accepted') {
      _beginAcceptedSession(session);
    } else if (_isOutgoingRinging(session)) {
      unawaited(_ringback.start());
    } else {
      unawaited(_ringback.stop());
    }
  }

  bool _isIncomingRinging(AppCallSession? session) =>
      session?.status == 'ringing' && session?.calleeRole == 'client';

  bool _isOutgoingRinging(AppCallSession? session) =>
      session?.status == 'ringing' && session?.callerRole == 'client';

  void _beginAcceptedSession(AppCallSession session) {
    _acceptedTransition ??= _stopRingbackThenStartRtc(session).whenComplete(() {
      _acceptedTransition = null;
    });
  }

  Future<void> _stopRingbackThenStartRtc(AppCallSession session) async {
    await _ringback.stop();
    if (!mounted || _session?.status != 'accepted') return;
    await _ensureRtc(session);
  }

  Future<void> _ensureRtc(AppCallSession session) async {
    if (_rtc != null || _rtcStarting) return;
    final attempt = ++_rtcAttempt;
    _rtcStarting = true;
    final rtc = AppCallRtcService(
      socket: ref.read(appCallSocketServiceProvider),
    );
    _rtc = rtc;
    _rtcStateSub = rtc.connectionStateStream.listen((state) {
      if (!mounted || attempt != _rtcAttempt || !identical(_rtc, rtc)) return;
      setState(() {
        _rtcState = state;
        if (state == AppCallRtcConnectionState.connected) {
          _errorMessage = null;
        } else if (state == AppCallRtcConnectionState.failed) {
          _errorMessage =
              'Call audio could not connect. Check your connection, '
              'then tap Retry audio.';
        } else if (state == AppCallRtcConnectionState.disconnected) {
          _errorMessage = 'Call audio was interrupted. Check your connection, '
              'then tap Retry audio.';
        }
      });
    });
    try {
      await rtc.start(
        session: session,
        isCaller: session.callerRole == 'client',
      );
      if (!mounted) {
        await rtc.dispose();
        return;
      }
    } catch (error) {
      if (attempt == _rtcAttempt) {
        await _rtcStateSub?.cancel();
        _rtcStateSub = null;
        _rtc = null;
      }
      await rtc.dispose();
      if (mounted && attempt == _rtcAttempt) {
        setState(() {
          _rtcState = AppCallRtcConnectionState.failed;
          _errorMessage = _callErrorMessage(error);
        });
      }
    } finally {
      if (attempt == _rtcAttempt) _rtcStarting = false;
    }
  }

  Future<void> _retryRtcConnection() async {
    final session = _session;
    if (_retryingRtc || session?.status != 'accepted') return;
    final oldRtc = _rtc;
    _rtc = null;
    _rtcAttempt += 1;
    _rtcStarting = false;
    setState(() {
      _retryingRtc = true;
      _rtcState = AppCallRtcConnectionState.connecting;
      _errorMessage = null;
    });
    await _rtcStateSub?.cancel();
    _rtcStateSub = null;
    await oldRtc?.dispose();
    if (!mounted) return;
    try {
      await _ensureRtc(session!);
    } finally {
      if (mounted) setState(() => _retryingRtc = false);
    }
  }

  void _scheduleTerminalClose(AppCallSession session) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_terminalCloseTimer != null) return;
    unawaited(VoipCallBridgeService.instance.endCall(widget.callId));
    _terminalCloseTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      // Leaving the call screen is the required terminal action. Capture the
      // optional messenger first, then navigate before attempting any
      // transient UI so a missing/deactivated ScaffoldMessenger can never
      // strand the user on an already-ended call.
      final messenger = ScaffoldMessenger.maybeOf(context);
      _leaveCallScreen();
      if (messenger?.mounted ?? false) {
        messenger!.showSnackBar(
          SnackBar(content: Text(_terminalMessage(session.status))),
        );
      }
    });
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _invalidateSessionRequest();
    setState(() => _ending = true);
    await _ringback.stop();
    var ended = false;
    try {
      final session =
          await ref.read(appCallServiceProvider).endCall(widget.callId);
      if (mounted) {
        setState(() {
          _session = session;
          _loading = false;
        });
      }
      try {
        await VoipCallBridgeService.instance.endCall(widget.callId);
      } catch (cleanupError) {
        debugPrint('[Call] native end cleanup failed: $cleanupError');
      }
      ended = true;
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _callErrorMessage(error));
        if (_isOutgoingRinging(_session)) unawaited(_ringback.start());
      }
    } finally {
      if (mounted) {
        setState(() => _ending = false);
        if (ended) _leaveCallScreen();
      }
    }
  }

  Future<void> _acceptCall() async {
    if (_accepting || _declining) return;
    _invalidateSessionRequest();
    setState(() => _accepting = true);
    try {
      if (Platform.isIOS &&
          await VoipCallBridgeService.instance.answerCall(widget.callId)) {
        await LocalNotificationService.instance.cancelIncomingCall(
          widget.callId,
        );
        return;
      }
      final session =
          await ref.read(appCallServiceProvider).acceptCall(widget.callId);
      await LocalNotificationService.instance.cancelIncomingCall(widget.callId);
      if (mounted) _applyRemoteSession(session);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _callErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _declineCall() async {
    if (_accepting || _declining) return;
    _invalidateSessionRequest();
    setState(() => _declining = true);
    var declined = false;
    try {
      var session =
          await ref.read(appCallServiceProvider).declineCall(widget.callId);
      if (!session.isTerminal) {
        session = await ref.read(appCallServiceProvider).endCall(widget.callId);
      }
      if (mounted) {
        setState(() {
          _session = session;
          _loading = false;
        });
      }
      await LocalNotificationService.instance.cancelIncomingCall(widget.callId);
      await VoipCallBridgeService.instance.endCall(widget.callId);
      declined = true;
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _callErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _declining = false);
        if (declined) _leaveCallScreen();
      }
    }
  }

  void _leaveCallScreen() {
    final session = _session;
    if ((session?.bookingType == 'artisan_job' ||
            session?.bookingType == 'job') &&
        session?.bookingId.isNotEmpty == true) {
      // Job routes sit above the root navigator. Seed the shell before
      // pushing the job so its Back action has a real destination after the
      // call screen (which may itself have been the cold-start root) closes.
      final router = GoRouter.of(context);
      router.go(AppRoutes.activity);
      router.push(AppRoutes.jobActivePath(session!.bookingId));
      return;
    }
    context.go(_returnRoute(session));
  }

  String _returnRoute(AppCallSession? session) {
    return switch (session?.bookingType) {
      'ride' => AppRoutes.rideTracking,
      'artisan_job' ||
      'job' when session?.bookingId.isNotEmpty == true =>
        AppRoutes.jobActivePath(session!.bookingId),
      _ => AppRoutes.home,
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final incomingRinging = _isIncomingRinging(session);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _loading) return;
        unawaited(incomingRinging ? _declineCall() : _endCall());
      },
      child: MyShopInAppCallView(
        peerName: _peerName(session),
        statusLabel: _statusLabel(session),
        contextLabel: _contextLabel(session),
        isLoading: _loading,
        isEnding: _ending,
        muted: _muted,
        speakerOn: _speakerOn,
        incomingRinging: incomingRinging,
        isAccepting: _accepting,
        isDeclining: _declining,
        errorMessage: _errorMessage,
        showRetryConnection: session?.status == 'accepted' &&
            (_rtcState == AppCallRtcConnectionState.failed ||
                (_rtc != null &&
                    _rtcState == AppCallRtcConnectionState.disconnected)),
        isRetryingConnection: _retryingRtc,
        onRetryConnection: _retryRtcConnection,
        onAcceptCall: _acceptCall,
        onDeclineCall: _declineCall,
        onToggleMuted: () {
          setState(() => _muted = !_muted);
          _rtc?.setMuted(_muted);
        },
        onToggleSpeaker: () {
          setState(() => _speakerOn = !_speakerOn);
          unawaited(_rtc?.setSpeakerOn(_speakerOn));
        },
        onEndCall: _endCall,
      ),
    );
  }

  String _peerName(AppCallSession? session) {
    if (session == null) return 'MyShop call';
    final callerIsClient = session.callerRole == 'client';
    final name = callerIsClient ? session.calleeName : session.callerName;
    return (name == null || name.trim().isEmpty) ? 'MyShop call' : name;
  }

  String _statusLabel(AppCallSession? session) {
    if (_loading) return 'Connecting...';
    return switch (session?.status) {
      'ringing' => _isIncomingRinging(session) ? 'Incoming call' : 'Ringing…',
      'accepted' => switch (_rtcState) {
          AppCallRtcConnectionState.connected => 'Connected',
          AppCallRtcConnectionState.failed => 'Connection failed',
          AppCallRtcConnectionState.disconnected => 'Connection interrupted',
          AppCallRtcConnectionState.connecting =>
            _retryingRtc ? 'Reconnecting…' : 'Connecting…',
        },
      'declined' => 'Declined',
      'ended' => 'Ended',
      'expired' => 'Missed',
      _ => 'Connecting...',
    };
  }

  String _contextLabel(AppCallSession? session) {
    return switch (session?.bookingType) {
      'ride' => 'Ride voice call',
      'artisan_job' || 'job' => 'Job voice call',
      _ => 'MyShop voice call',
    };
  }

  String _terminalMessage(String status) {
    return switch (status) {
      'declined' => 'Call declined',
      'expired' => 'Call missed',
      _ => 'Call ended',
    };
  }

  String _callErrorMessage(Object error) {
    if (error is ApiException) {
      return userSafeApiErrorMessage(
        error,
        fallback: 'Call could not connect. Please try again.',
        conflictMessage:
            'This call is no longer available. Return to the booking and try again.',
      );
    }
    return 'Call could not connect. Please try again.';
  }
}
