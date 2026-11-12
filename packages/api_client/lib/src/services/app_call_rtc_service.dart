import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'app_call_service.dart';
import 'app_call_socket_service.dart';

enum AppCallRtcConnectionState { connecting, connected, disconnected, failed }

/// Bounds the time a call may remain in WebRTC's `connecting` state.
///
/// The first timer gives ICE one automatic recovery attempt. The second timer
/// makes the failure visible to the UI instead of leaving both participants on
/// an endless "Connecting..." screen.
@visibleForTesting
final class AppCallConnectionWatchdog {
  AppCallConnectionWatchdog({
    required this.retryAfter,
    required this.failAfter,
    required this.onRetry,
    required this.onFailure,
  }) : assert(failAfter > retryAfter);

  final Duration retryAfter;
  final Duration failAfter;
  final VoidCallback onRetry;
  final VoidCallback onFailure;

  Timer? _retryTimer;
  Timer? _failureTimer;

  void start() {
    cancel();
    _retryTimer = Timer(retryAfter, onRetry);
    _failureTimer = Timer(failAfter, onFailure);
  }

  void cancel() {
    _retryTimer?.cancel();
    _failureTimer?.cancel();
    _retryTimer = null;
    _failureTimer = null;
  }

  void dispose() => cancel();
}

typedef AppCallSignalHandler = Future<void> Function(AppCallSignal signal);
typedef AppCallSignalErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Serialises WebRTC signaling messages and retains messages received before
/// the peer connection is ready.
///
/// Kept separate from the native WebRTC objects so ordering and early-message
/// behaviour can be covered by ordinary unit tests.
@visibleForTesting
final class AppCallSignalSerialQueue {
  AppCallSignalSerialQueue({this.onError});

  final AppCallSignalErrorHandler? onError;
  final List<AppCallSignal> _pending = <AppCallSignal>[];
  Future<void> _tail = Future<void>.value();
  bool _ready = false;
  bool _disposed = false;

  @visibleForTesting
  int get pendingCount => _pending.length;

  void add(AppCallSignal signal, AppCallSignalHandler handler) {
    if (_disposed) return;
    if (!_ready) {
      _pending.add(signal);
      return;
    }
    _append(signal, handler);
  }

  Future<void> markReady(AppCallSignalHandler handler) async {
    if (_disposed || _ready) return;
    _ready = true;
    final pending = List<AppCallSignal>.of(_pending);
    _pending.clear();
    for (final signal in pending) {
      _append(signal, handler);
    }
    await _tail;
  }

  Future<void> drain() => _tail;

  void dispose() {
    _disposed = true;
    _pending.clear();
  }

  void _append(AppCallSignal signal, AppCallSignalHandler handler) {
    _tail = _tail.then((_) async {
      if (_disposed) return;
      try {
        await handler(signal);
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    });
  }
}

class AppCallRtcService {
  AppCallRtcService({
    required AppCallSocketService socket,
    Future<AppCallSession> Function(String callId)? refreshSession,
    Future<MediaStream> Function()? acquireMicrophone,
    Future<RTCPeerConnection> Function(Map<String, dynamic>)? createPeer,
    Duration automaticRetryAfter = const Duration(seconds: 12),
    Duration connectionTimeout = const Duration(seconds: 30),
  })  : _socket = socket,
        _refreshSession = refreshSession,
        _acquireMicrophone = acquireMicrophone,
        _createPeer = createPeer,
        _automaticRetryAfter = automaticRetryAfter,
        _connectionTimeout = connectionTimeout;

  final AppCallSocketService _socket;
  final Future<AppCallSession> Function(String callId)? _refreshSession;
  final Future<MediaStream> Function()? _acquireMicrophone;
  final Future<RTCPeerConnection> Function(Map<String, dynamic>)? _createPeer;
  final Completer<void> _startupStopped = Completer<void>();
  bool _recoveryPending = false;
  bool _recovering = false;
  Future<void>? _mediaCleanup;
  String _phase = 'idle';

  bool get _inactive =>
      _disposed || _connectionState == AppCallRtcConnectionState.failed;
  final Duration _automaticRetryAfter;
  final Duration _connectionTimeout;
  final StreamController<AppCallRtcConnectionState> _connectionController =
      StreamController<AppCallRtcConnectionState>.broadcast();
  late final AppCallSignalSerialQueue _signalQueue = AppCallSignalSerialQueue(
    onError: _handleSignalError,
  );

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  StreamSubscription<AppCallSignal>? _signalSub;
  StreamSubscription<String>? _participantSub;
  StreamSubscription<bool>? _socketConnectionSub;
  AppCallConnectionWatchdog? _connectionWatchdog;
  String? _callId;
  String _rtcProvider = 'unknown';
  bool _isCaller = false;
  bool _started = false;
  bool _disposed = false;
  bool _everConnected = false;
  bool _hasRemoteDescription = false;
  bool _localDescriptionSignaled = false;
  String? _lastRemoteOfferSdp;
  String? _lastRemoteAnswerSdp;
  Map<String, dynamic>? _lastOffer;
  Map<String, dynamic>? _lastAnswer;
  Future<void> _offerTail = Future<void>.value();
  final Stopwatch _startupClock = Stopwatch();
  bool _firstRemoteSignalLogged = false;
  AppCallRtcConnectionState _connectionState =
      AppCallRtcConnectionState.disconnected;

  final List<Map<String, dynamic>> _localIceCandidates =
      <Map<String, dynamic>>[];
  int _sentLocalCandidateCount = 0;
  final List<_PendingIceCandidate> _pendingRemoteIceCandidates =
      <_PendingIceCandidate>[];
  final Set<String> _seenRemoteIceCandidateKeys = <String>{};
  final Map<String, int> _localIceTypeCounts = <String, int>{};
  final Map<String, int> _remoteIceTypeCounts = <String, int>{};

  Stream<AppCallRtcConnectionState> get connectionStateStream =>
      _connectionController.stream;

  AppCallRtcConnectionState get connectionState => _connectionState;

  Future<void> start({
    required AppCallSession session,
    required bool isCaller,
    Future<void> Function()? prepareAudio,
  }) async {
    if (_started || _disposed) return;
    _started = true;
    _callId = session.callId;
    _rtcProvider = session.rtcProvider.trim().isEmpty
        ? 'unknown'
        : session.rtcProvider.trim();
    _isCaller = isCaller;
    _startupClock
      ..reset()
      ..start();
    _firstRemoteSignalLogged = false;
    _everConnected = false;
    _publishConnectionState(AppCallRtcConnectionState.connecting);
    final iceConfig = appCallIceServerSummary(session.iceServers);
    _log(
      'start role=${isCaller ? 'caller' : 'callee'} '
      'rtcProvider=$_rtcProvider iceServers=${session.iceServers.length} '
      'iceUrls=${iceConfig.totalUrls} stun=${iceConfig.stunUrls} '
      'turn=${iceConfig.turnUrls}',
    );

    // The deadline includes ringback cleanup, permission prompts and native
    // initialization, not just ICE negotiation.
    _startConnectionWatchdog();
    final startup = _startMedia(session, prepareAudio);
    await Future.any<void>([startup, _startupStopped.future]);
  }

  Future<void> _startMedia(
    AppCallSession session,
    Future<void> Function()? prepareAudio,
  ) async {
    try {
      _signalSub = _socket.signalStream.listen((signal) {
        if (signal.callId != _callId || _inactive) return;
        _log('signal rx type=${signal.type}');
        _signalQueue.add(signal, _handleSignal);
      });
      _participantSub = _socket.participantJoinedStream.listen((callId) {
        if (callId != _callId || _inactive) return;
        unawaited(_replayNegotiation('participant joined'));
      });
      _socketConnectionSub = _socket.connectionStream.listen((connected) {
        if (!connected || _inactive) return;
        unawaited(_replayNegotiation('socket connected'));
      });

      _phase = 'audio cleanup';
      if (prepareAudio != null) {
        await prepareAudio().timeout(const Duration(seconds: 3));
        if (_inactive) return;
      }
      _log('audio cleanup ready');
      _phase = 'microphone';
      final stream = await (_acquireMicrophone?.call() ??
          navigator.mediaDevices.getUserMedia({
            'audio': {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            },
            'video': false,
          }));
      if (_inactive) {
        await _releaseStream(stream);
        return;
      }
      _localStream = stream;
      _log('microphone ready elapsedMs=${_startupClock.elapsedMilliseconds}');

      final iceServers = session.iceServers;
      _phase = 'peer creation';
      final peer = await (_createPeer ?? createPeerConnection)({
        'iceServers': iceServers.isNotEmpty
            ? iceServers
            : const [
                {
                  'urls': ['stun:stun.l.google.com:19302'],
                },
              ],
        'sdpSemantics': 'unified-plan',
      });
      if (_inactive) {
        await _cleanupNativeResource(peer.close);
        return;
      }
      _peer = peer;
      _bindPeerCallbacks(peer);
      for (final track in _localStream!.getAudioTracks()) {
        await peer.addTrack(track, stream);
        if (_inactive) return;
      }
      _log('peer ready elapsedMs=${_startupClock.elapsedMilliseconds}');
      _phase = 'signaling';

      // Any offer/answer/ICE received while microphone permission or native peer
      // setup was in progress is now applied in arrival order.
      await _signalQueue.markReady(_handleSignal);
      if (_inactive) return;

      await _socket.joinCall(session.callId);
      if (_inactive) return;
      if (_isCaller) await _queueOfferSend();
      if (_inactive) return;
      _phase = 'ICE negotiation';
      if (_recoveryPending) {
        _recoveryPending = false;
        unawaited(_attemptConnectionRecovery('deferred startup recovery'));
      }
    } catch (error, stackTrace) {
      if (_inactive) return;
      _handleSignalError(error, stackTrace);
      rethrow;
    }
  }

  void _startConnectionWatchdog() {
    _connectionWatchdog?.dispose();
    _connectionWatchdog = AppCallConnectionWatchdog(
      retryAfter: _automaticRetryAfter,
      failAfter: _connectionTimeout,
      onRetry: () {
        if (_inactive ||
            _connectionState == AppCallRtcConnectionState.connected) {
          return;
        }
        if (_peer == null || _phase != 'ICE negotiation') {
          _recoveryPending = true;
          return;
        }
        unawaited(_attemptConnectionRecovery('connection watchdog'));
      },
      onFailure: () {
        if (_inactive ||
            _connectionState == AppCallRtcConnectionState.connected) {
          return;
        }
        _log('connection timeout phase=$_phase');
        _logIceSummary('connection timeout');
        _publishConnectionState(AppCallRtcConnectionState.failed);
      },
    )..start();
  }

  void _bindPeerCallbacks(RTCPeerConnection peer) {
    peer.onIceCandidate = (candidate) {
      if (_inactive || candidate.candidate?.isEmpty != false) return;
      final data = <String, dynamic>{
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      _localIceCandidates.add(data);
      final type = appCallIceCandidateType(candidate.candidate!);
      _localIceTypeCounts.update(type, (count) => count + 1, ifAbsent: () => 1);
      _log(
        'local ICE ${_candidateSummary(candidate.candidate!)} '
        'count=${_localIceCandidates.length}',
      );
      if (_localDescriptionSignaled) {
        _sendUnsentLocalCandidates();
      }
    };
    peer.onTrack = (event) {
      var audioTrackCount = 0;
      for (final track in event.streams.expand(
        (stream) => stream.getAudioTracks(),
      )) {
        track.enabled = true;
        audioTrackCount += 1;
      }
      _log(
        'remote track kind=${event.track.kind} audioTracks=$audioTrackCount',
      );
    };
    peer.onConnectionState = (state) {
      _log('peer state=${state.name}');
      _publishConnectionState(appCallRtcStateFromPeerState(state));
    };
    peer.onIceConnectionState = (state) {
      _log('ICE state=${state.name}');
      _publishConnectionState(appCallRtcStateFromIceState(state));
    };
    peer.onIceGatheringState = (state) {
      _log('ICE gathering=${state.name}');
    };
    peer.onSignalingState = (state) {
      _log('signaling state=${state.name}');
    };
  }

  Future<void> _replayNegotiation(String reason) async {
    try {
      _log('$reason; replaying negotiation');
      if (_isCaller) {
        await _queueOfferSend();
      } else {
        final answer = _lastAnswer;
        if (answer == null) {
          // The caller's fresh offer will produce an answer and candidates.
          // Do not emit callee candidates before their owning SDP description.
          return;
        }
        _sendSignal(type: 'answer', data: answer);
      }
      if (_inactive) return;
      final candidates = List<Map<String, dynamic>>.of(_localIceCandidates);
      for (final candidate in candidates) {
        _sendSignal(type: 'ice', data: candidate);
      }
      _log('replayed local ICE count=${candidates.length}');
    } catch (error, stackTrace) {
      _handleSignalError(error, stackTrace);
    }
  }

  Future<void> _attemptConnectionRecovery(String reason) async {
    if (_recovering ||
        _inactive ||
        _connectionState == AppCallRtcConnectionState.connected) return;
    _recovering = true;
    try {
      final callId = _callId;
      final peer = _peer;
      if (_inactive || callId == null || peer == null) return;
      _log('$reason; attempting one ICE recovery');
      final refresh = _refreshSession;
      if (refresh != null) {
        try {
          final session =
              await refresh(callId).timeout(const Duration(seconds: 6));
          if (_inactive ||
              _connectionState == AppCallRtcConnectionState.connected) return;
          if (session.callId != callId || !session.isAccepted) return;
          final servers = session.iceServers;
          // Never downgrade working relay configuration to STUN-only fallback.
          if (appCallIceServerSummary(servers).turnUrls > 0) {
            await peer.setConfiguration({'iceServers': servers});
            if (_inactive) return;
            _rtcProvider = session.rtcProvider;
            _log('recovery TURN configuration applied');
          } else {
            _log('recovery refresh has no TURN servers');
          }
        } catch (_) {
          _log('recovery refresh unavailable; retaining ICE configuration');
        }
      }
      if (_inactive || _connectionState == AppCallRtcConnectionState.connected)
        return;
      _logIceSummary('before recovery');
      await _socket.joinCall(callId);
      if (_inactive || _connectionState == AppCallRtcConnectionState.connected)
        return;
      if (_isCaller) {
        _lastOffer = null;
        _localDescriptionSignaled = false;
        _localIceCandidates.clear();
        _localIceTypeCounts.clear();
        _sentLocalCandidateCount = 0;
        await peer.restartIce();
        if (_inactive) return;
        await _queueOfferSend(iceRestart: true);
        return;
      }
      // Rejoining emits participant_joined to the caller. Replay the latest
      // answer as a belt-and-braces recovery when the original answer was lost.
      final answer = _lastAnswer;
      if (answer != null) _sendSignal(type: 'answer', data: answer);
      for (final candidate
          in List<Map<String, dynamic>>.of(_localIceCandidates)) {
        _sendSignal(type: 'ice', data: candidate);
      }
    } catch (error, stackTrace) {
      _handleSignalError(error, stackTrace);
    } finally {
      _recovering = false;
    }
  }

  Future<void> _queueOfferSend({bool iceRestart = false}) {
    final operation =
        _offerTail.then((_) => _sendOrCreateOffer(iceRestart: iceRestart));
    _offerTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _handleSignalError(error, stackTrace);
      },
    );
    return operation;
  }

  Future<void> _sendOrCreateOffer({bool iceRestart = false}) async {
    final callId = _callId;
    final peer = _peer;
    if (_inactive || callId == null || peer == null) return;
    final cached = iceRestart ? null : _lastOffer;
    if (cached != null) {
      _sendSignal(type: 'offer', data: cached);
      return;
    }
    final offer = await peer.createOffer({
      'offerToReceiveAudio': true,
      if (iceRestart) 'iceRestart': true,
    });
    if (_inactive) return;
    await peer.setLocalDescription(offer);
    if (_inactive) return;
    final data = <String, dynamic>{'sdp': offer.sdp, 'sdpType': offer.type};
    _lastOffer = data;
    _sendSignal(type: 'offer', data: data);
    _localDescriptionSignaled = true;
    _sendUnsentLocalCandidates();
  }

  Future<void> _handleSignal(AppCallSignal signal) async {
    final peer = _peer;
    if (_inactive || peer == null) return;
    if (!_firstRemoteSignalLogged) {
      _firstRemoteSignalLogged = true;
      _log(
        'first remote signal type=${signal.type} '
        'elapsedMs=${_startupClock.elapsedMilliseconds}',
      );
    }
    switch (signal.type) {
      case 'offer':
        final sdp = signal.data['sdp'] as String?;
        if (sdp == null) return;
        if (sdp == _lastRemoteOfferSdp) {
          if (!_isCaller) {
            await _replayNegotiation('duplicate offer');
          }
          return;
        }
        await peer.setRemoteDescription(
          RTCSessionDescription(
            sdp,
            signal.data['sdpType'] as String? ?? 'offer',
          ),
        );
        if (_inactive) return;
        _lastRemoteOfferSdp = sdp;
        _hasRemoteDescription = true;
        await _flushPendingRemoteIceCandidates();
        final answer = await peer.createAnswer({'offerToReceiveAudio': true});
        if (_inactive) return;
        await peer.setLocalDescription(answer);
        if (_inactive) return;
        final data = <String, dynamic>{
          'sdp': answer.sdp,
          'sdpType': answer.type,
        };
        _lastAnswer = data;
        _sendSignal(type: 'answer', data: data);
        _localDescriptionSignaled = true;
        _sendUnsentLocalCandidates();
      case 'answer':
        final sdp = signal.data['sdp'] as String?;
        if (sdp == null || sdp == _lastRemoteAnswerSdp) return;
        await peer.setRemoteDescription(
          RTCSessionDescription(
            sdp,
            signal.data['sdpType'] as String? ?? 'answer',
          ),
        );
        if (_inactive) return;
        _lastRemoteAnswerSdp = sdp;
        _hasRemoteDescription = true;
        await _flushPendingRemoteIceCandidates();
      case 'ice':
        final candidateSdp = signal.data['candidate'] as String?;
        if (candidateSdp == null || candidateSdp.isEmpty) return;
        await _bufferOrAddRemoteIceCandidate(
          RTCIceCandidate(
            candidateSdp,
            signal.data['sdpMid'] as String?,
            (signal.data['sdpMLineIndex'] as num?)?.toInt(),
          ),
        );
    }
  }

  Future<void> _bufferOrAddRemoteIceCandidate(RTCIceCandidate candidate) async {
    final key = _candidateKey(candidate);
    if (!_seenRemoteIceCandidateKeys.add(key)) return;
    final type = appCallIceCandidateType(candidate.candidate ?? '');
    _remoteIceTypeCounts.update(type, (count) => count + 1, ifAbsent: () => 1);
    final pending = _PendingIceCandidate(candidate: candidate, key: key);
    if (!_hasRemoteDescription) {
      _pendingRemoteIceCandidates.add(pending);
      _log(
        'remote ICE buffered ${_candidateSummary(candidate.candidate ?? '')} '
        'count=${_pendingRemoteIceCandidates.length}',
      );
      return;
    }
    await _addRemoteIceCandidate(pending);
  }

  Future<void> _flushPendingRemoteIceCandidates() async {
    if (!_hasRemoteDescription || _pendingRemoteIceCandidates.isEmpty) return;
    final pending = List<_PendingIceCandidate>.of(_pendingRemoteIceCandidates);
    _pendingRemoteIceCandidates.clear();
    _log('flushing remote ICE count=${pending.length}');
    for (final candidate in pending) {
      await _addRemoteIceCandidate(candidate);
    }
  }

  Future<void> _addRemoteIceCandidate(_PendingIceCandidate pending) async {
    final peer = _peer;
    if (_inactive || peer == null) return;
    try {
      await peer.addCandidate(pending.candidate);
      _log(
        'remote ICE added '
        '${_candidateSummary(pending.candidate.candidate ?? '')}',
      );
    } catch (error) {
      // Permit a replayed candidate to be retried if native WebRTC rejected it
      // during a transient signaling-state transition.
      _seenRemoteIceCandidateKeys.remove(pending.key);
      _log('remote ICE add failed: $error');
    }
  }

  void _sendUnsentLocalCandidates() {
    if (!_localDescriptionSignaled || _inactive) return;
    while (_sentLocalCandidateCount < _localIceCandidates.length) {
      final candidate = _localIceCandidates[_sentLocalCandidateCount];
      _sentLocalCandidateCount += 1;
      _sendSignal(type: 'ice', data: candidate);
    }
  }

  void _sendSignal({required String type, required Map<String, dynamic> data}) {
    final callId = _callId;
    if (_inactive || callId == null) return;
    _log('signal tx type=$type');
    _socket.sendSignal(callId: callId, type: type, data: data);
  }

  void setMuted(bool muted) {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> setSpeakerOn(bool enabled) => Helper.setSpeakerphoneOn(enabled);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_startupStopped.isCompleted) _startupStopped.complete();
    _connectionWatchdog?.dispose();
    _signalQueue.dispose();
    _started = false;
    await _releaseMedia();
    await _signalSub?.cancel();
    await _participantSub?.cancel();
    await _socketConnectionSub?.cancel();
    _connectionWatchdog = null;
    _signalSub = null;
    _participantSub = null;
    _socketConnectionSub = null;
    _callId = null;
    _rtcProvider = 'unknown';
    _isCaller = false;
    _hasRemoteDescription = false;
    _localDescriptionSignaled = false;
    _lastRemoteOfferSdp = null;
    _lastRemoteAnswerSdp = null;
    _lastOffer = null;
    _lastAnswer = null;
    _localIceCandidates.clear();
    _pendingRemoteIceCandidates.clear();
    _seenRemoteIceCandidateKeys.clear();
    _localIceTypeCounts.clear();
    _remoteIceTypeCounts.clear();
    _sentLocalCandidateCount = 0;
    _startupClock.stop();
    _firstRemoteSignalLogged = false;
    _everConnected = false;
    await _connectionController.close();
  }

  Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      await _cleanupNativeResource(track.stop);
    }
    await _cleanupNativeResource(stream.dispose);
  }

  Future<void> _cleanupNativeResource(Future<void> Function() release) async {
    try {
      await release().timeout(const Duration(seconds: 2));
    } catch (_) {
      _log('native media cleanup failed or timed out');
    }
  }

  Future<void> _releaseMedia() => _mediaCleanup ??= _releaseCurrentMedia();

  Future<void> _releaseCurrentMedia() async {
    final peer = _peer;
    final stream = _localStream;
    _peer = null;
    _localStream = null;
    try {
      if (peer != null) await _cleanupNativeResource(peer.close);
    } finally {
      if (stream != null) await _releaseStream(stream);
    }
  }

  void _publishConnectionState(AppCallRtcConnectionState state) {
    if (_disposed) return;
    final resolved = mergeAppCallRtcConnectionState(_connectionState, state);
    if (resolved == _connectionState) return;
    _connectionState = resolved;
    if (resolved == AppCallRtcConnectionState.connected ||
        resolved == AppCallRtcConnectionState.failed) {
      if (resolved == AppCallRtcConnectionState.connected) {
        _everConnected = true;
      }
      _connectionWatchdog?.cancel();
      if (resolved == AppCallRtcConnectionState.failed) {
        if (!_startupStopped.isCompleted) _startupStopped.complete();
        _signalQueue.dispose();
        unawaited(
          _releaseMedia().catchError((Object _) {
            _log('media cleanup failed');
          }),
        );
      }
      _logIceSummary('connection ${resolved.name}');
      _log(
        'terminal connection state=${resolved.name} '
        'elapsedMs=${_startupClock.elapsedMilliseconds}',
      );
      _startupClock.stop();
    } else if (shouldRestartAppCallConnectionWatchdog(
          everConnected: _everConnected,
          state: resolved,
        ) &&
        _peer != null) {
      _startupClock
        ..reset()
        ..start();
      _startConnectionWatchdog();
    }
    if (!_connectionController.isClosed) {
      _connectionController.add(resolved);
    }
  }

  void _handleSignalError(Object error, StackTrace stackTrace) {
    _log('setup failed phase=$_phase errorType=${error.runtimeType}');
    _publishConnectionState(AppCallRtcConnectionState.failed);
  }

  void _logIceSummary(String reason) {
    _log(
      '$reason rtcProvider=$_rtcProvider '
      'localIce=${_formatIceCounts(_localIceTypeCounts)} '
      'remoteIce=${_formatIceCounts(_remoteIceTypeCounts)}',
    );
  }

  void _log(String message) {
    debugPrint('[CALL-RTC][${_callId ?? 'unassigned'}] '
        'elapsedMs=${_startupClock.elapsedMilliseconds} $message');
  }
}

@visibleForTesting
AppCallRtcConnectionState appCallRtcStateFromPeerState(
  RTCPeerConnectionState state,
) {
  return switch (state) {
    RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
      AppCallRtcConnectionState.connected,
    RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
    RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
      AppCallRtcConnectionState.disconnected,
    RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
      AppCallRtcConnectionState.failed,
    _ => AppCallRtcConnectionState.connecting,
  };
}

@visibleForTesting
AppCallRtcConnectionState appCallRtcStateFromIceState(
  RTCIceConnectionState state,
) {
  return switch (state) {
    RTCIceConnectionState.RTCIceConnectionStateConnected ||
    RTCIceConnectionState.RTCIceConnectionStateCompleted =>
      AppCallRtcConnectionState.connected,
    RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
    RTCIceConnectionState.RTCIceConnectionStateClosed =>
      AppCallRtcConnectionState.disconnected,
    RTCIceConnectionState.RTCIceConnectionStateFailed =>
      AppCallRtcConnectionState.failed,
    _ => AppCallRtcConnectionState.connecting,
  };
}

/// Arbitrates callbacks from the peer and ICE state machines.
///
/// Native WebRTC may report ICE `checking` after the peer has already reported
/// `connected`. That stale callback must not send the UI back to an indefinite
/// Connecting state. A failed RTC instance is terminal; the call screen creates
/// a fresh instance when the user explicitly retries.
@visibleForTesting
AppCallRtcConnectionState mergeAppCallRtcConnectionState(
  AppCallRtcConnectionState current,
  AppCallRtcConnectionState incoming,
) {
  if (current == AppCallRtcConnectionState.failed ||
      incoming == AppCallRtcConnectionState.failed) {
    return AppCallRtcConnectionState.failed;
  }
  if (current == AppCallRtcConnectionState.connected &&
      incoming == AppCallRtcConnectionState.connecting) {
    return AppCallRtcConnectionState.connected;
  }
  return incoming;
}

/// A disconnect during initial ICE negotiation must keep the original
/// absolute deadline. Only a call that previously connected gets a fresh
/// recovery window after disconnecting.
@visibleForTesting
bool shouldRestartAppCallConnectionWatchdog({
  required bool everConnected,
  required AppCallRtcConnectionState state,
}) =>
    everConnected && state == AppCallRtcConnectionState.disconnected;

String _candidateKey(RTCIceCandidate candidate) =>
    '${candidate.candidate}|${candidate.sdpMid}|${candidate.sdpMLineIndex}';

String _candidateSummary(String candidate) {
  final parts = candidate.trim().split(RegExp(r'\s+'));
  final protocol = parts.length > 2 ? parts[2].toLowerCase() : 'unknown';
  final typeIndex = parts.indexOf('typ');
  final type = typeIndex >= 0 && typeIndex + 1 < parts.length
      ? parts[typeIndex + 1].toLowerCase()
      : 'unknown';
  return 'type=$type protocol=$protocol';
}

@visibleForTesting
String appCallIceCandidateType(String candidate) {
  final parts = candidate.trim().split(RegExp(r'\s+'));
  final typeIndex = parts.indexOf('typ');
  return typeIndex >= 0 && typeIndex + 1 < parts.length
      ? parts[typeIndex + 1].toLowerCase()
      : 'unknown';
}

@visibleForTesting
AppCallIceServerSummary appCallIceServerSummary(
  List<Map<String, dynamic>> servers,
) {
  var total = 0;
  var stun = 0;
  var turn = 0;
  for (final server in servers) {
    final raw = server['urls'];
    final urls = raw is String
        ? <String>[raw]
        : raw is List
            ? raw.whereType<String>()
            : const Iterable<String>.empty();
    for (final url in urls) {
      total += 1;
      final scheme = url.trim().toLowerCase();
      if (scheme.startsWith('stun:') || scheme.startsWith('stuns:')) {
        stun += 1;
      } else if (scheme.startsWith('turn:') || scheme.startsWith('turns:')) {
        turn += 1;
      }
    }
  }
  return AppCallIceServerSummary(
    totalUrls: total,
    stunUrls: stun,
    turnUrls: turn,
  );
}

@visibleForTesting
final class AppCallIceServerSummary {
  const AppCallIceServerSummary({
    required this.totalUrls,
    required this.stunUrls,
    required this.turnUrls,
  });

  final int totalUrls;
  final int stunUrls;
  final int turnUrls;
}

String _formatIceCounts(Map<String, int> counts) {
  if (counts.isEmpty) return 'none';
  final entries = counts.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries.map((entry) => '${entry.key}:${entry.value}').join(',');
}

final class _PendingIceCandidate {
  const _PendingIceCandidate({required this.candidate, required this.key});

  final RTCIceCandidate candidate;
  final String key;
}
