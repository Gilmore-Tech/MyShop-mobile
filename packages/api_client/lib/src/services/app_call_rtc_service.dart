import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'app_call_service.dart';
import 'app_call_socket_service.dart';

enum AppCallRtcConnectionState { connecting, connected, disconnected, failed }

typedef AppCallSignalHandler = Future<void> Function(AppCallSignal signal);
typedef AppCallSignalErrorHandler =
    void Function(Object error, StackTrace stackTrace);

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
  AppCallRtcService({required AppCallSocketService socket}) : _socket = socket;

  final AppCallSocketService _socket;
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
  String? _callId;
  bool _isCaller = false;
  bool _started = false;
  bool _disposed = false;
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

  Stream<AppCallRtcConnectionState> get connectionStateStream =>
      _connectionController.stream;

  AppCallRtcConnectionState get connectionState => _connectionState;

  Future<void> start({
    required AppCallSession session,
    required bool isCaller,
  }) async {
    if (_started || _disposed) return;
    _started = true;
    _callId = session.callId;
    _isCaller = isCaller;
    _startupClock
      ..reset()
      ..start();
    _firstRemoteSignalLogged = false;
    _publishConnectionState(AppCallRtcConnectionState.connecting);
    _log(
      'start role=${isCaller ? 'caller' : 'callee'} '
      'iceServers=${session.iceServers.length}',
    );

    _signalSub = _socket.signalStream.listen((signal) {
      if (signal.callId != _callId || _disposed) return;
      _log('signal rx type=${signal.type}');
      _signalQueue.add(signal, _handleSignal);
    });
    _participantSub = _socket.participantJoinedStream.listen((callId) {
      if (callId != _callId || _disposed) return;
      unawaited(_replayNegotiation('participant joined'));
    });
    _socketConnectionSub = _socket.connectionStream.listen((connected) {
      if (!connected || _disposed) return;
      unawaited(_replayNegotiation('socket connected'));
    });

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    _log('microphone ready elapsedMs=${_startupClock.elapsedMilliseconds}');

    final iceServers = session.iceServers;
    final peer = await createPeerConnection({
      'iceServers': iceServers.isNotEmpty
          ? iceServers
          : const [
              {
                'urls': ['stun:stun.l.google.com:19302'],
              },
            ],
      'sdpSemantics': 'unified-plan',
    });
    _bindPeerCallbacks(peer);
    for (final track in _localStream!.getAudioTracks()) {
      await peer.addTrack(track, _localStream!);
    }
    _peer = peer;
    _log('peer ready elapsedMs=${_startupClock.elapsedMilliseconds}');

    // Any offer/answer/ICE received while microphone permission or native peer
    // setup was in progress is now applied in arrival order.
    await _signalQueue.markReady(_handleSignal);
    if (_disposed) return;

    await _socket.joinCall(session.callId);
    if (_isCaller) await _queueOfferSend();
  }

  void _bindPeerCallbacks(RTCPeerConnection peer) {
    peer.onIceCandidate = (candidate) {
      if (_disposed || candidate.candidate?.isEmpty != false) return;
      final data = <String, dynamic>{
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      _localIceCandidates.add(data);
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
      if (_disposed) return;
      final candidates = List<Map<String, dynamic>>.of(_localIceCandidates);
      for (final candidate in candidates) {
        _sendSignal(type: 'ice', data: candidate);
      }
      _log('replayed local ICE count=${candidates.length}');
    } catch (error, stackTrace) {
      _handleSignalError(error, stackTrace);
    }
  }

  Future<void> _queueOfferSend() {
    final operation = _offerTail.then((_) => _sendOrCreateOffer());
    _offerTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _handleSignalError(error, stackTrace);
      },
    );
    return operation;
  }

  Future<void> _sendOrCreateOffer() async {
    final callId = _callId;
    final peer = _peer;
    if (_disposed || callId == null || peer == null) return;
    final cached = _lastOffer;
    if (cached != null) {
      _sendSignal(type: 'offer', data: cached);
      return;
    }
    final offer = await peer.createOffer({'offerToReceiveAudio': true});
    if (_disposed) return;
    await peer.setLocalDescription(offer);
    if (_disposed) return;
    final data = <String, dynamic>{'sdp': offer.sdp, 'sdpType': offer.type};
    _lastOffer = data;
    _sendSignal(type: 'offer', data: data);
    _localDescriptionSignaled = true;
    _sendUnsentLocalCandidates();
  }

  Future<void> _handleSignal(AppCallSignal signal) async {
    final peer = _peer;
    if (_disposed || peer == null) return;
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
        if (_disposed) return;
        _lastRemoteOfferSdp = sdp;
        _hasRemoteDescription = true;
        await _flushPendingRemoteIceCandidates();
        final answer = await peer.createAnswer({'offerToReceiveAudio': true});
        if (_disposed) return;
        await peer.setLocalDescription(answer);
        if (_disposed) return;
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
        if (_disposed) return;
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
    if (_disposed || peer == null) return;
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
    if (!_localDescriptionSignaled || _disposed) return;
    while (_sentLocalCandidateCount < _localIceCandidates.length) {
      final candidate = _localIceCandidates[_sentLocalCandidateCount];
      _sentLocalCandidateCount += 1;
      _sendSignal(type: 'ice', data: candidate);
    }
  }

  void _sendSignal({required String type, required Map<String, dynamic> data}) {
    final callId = _callId;
    if (_disposed || callId == null) return;
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
    _started = false;
    await _signalSub?.cancel();
    await _participantSub?.cancel();
    await _socketConnectionSub?.cancel();
    _signalQueue.dispose();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    await _peer?.close();
    _peer = null;
    _localStream = null;
    _signalSub = null;
    _participantSub = null;
    _socketConnectionSub = null;
    _callId = null;
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
    _sentLocalCandidateCount = 0;
    _startupClock.stop();
    _firstRemoteSignalLogged = false;
    await _connectionController.close();
  }

  void _publishConnectionState(AppCallRtcConnectionState state) {
    if (_disposed || state == _connectionState) return;
    _connectionState = state;
    if (state == AppCallRtcConnectionState.connected ||
        state == AppCallRtcConnectionState.failed) {
      _log(
        'terminal connection state=${state.name} '
        'elapsedMs=${_startupClock.elapsedMilliseconds}',
      );
      _startupClock.stop();
    }
    if (!_connectionController.isClosed) {
      _connectionController.add(state);
    }
  }

  void _handleSignalError(Object error, StackTrace stackTrace) {
    _log('signal handling failed: $error');
  }

  void _log(String message) {
    debugPrint('[CALL-RTC][${_callId ?? 'unassigned'}] $message');
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

final class _PendingIceCandidate {
  const _PendingIceCandidate({required this.candidate, required this.key});

  final RTCIceCandidate candidate;
  final String key;
}
