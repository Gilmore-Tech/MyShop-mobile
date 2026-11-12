import 'dart:async';

import 'package:api_client/src/services/app_call_rtc_service.dart';
import 'package:api_client/src/services/app_call_service.dart';
import 'package:api_client/src/services/app_call_socket_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mocktail/mocktail.dart';

class _Socket extends Mock implements AppCallSocketService {}

class _Stream extends Mock implements MediaStream {}

class _Track extends Mock implements MediaStreamTrack {}

class _Peer extends Mock implements RTCPeerConnection {
  @override
  void Function(RTCPeerConnectionState)? onConnectionState;
}

AppCallSession _session({bool relay = false}) => AppCallSession.fromJson({
      'callId': 'call-1',
      'status': 'accepted',
      'rtcProvider': relay ? 'cloudflare_turn' : 'stun_fallback',
      if (relay)
        'rtcToken': {
          'iceServers': [
            {
              'urls': 'turn:relay.example.com:3478',
              'username': 'user',
              'credential': 'secret',
            },
          ],
        },
    });

void main() {
  setUpAll(() => registerFallbackValue(RTCSessionDescription('', 'offer')));
  late _Socket socket;
  late _Stream stream;
  late _Track track;
  late _Peer peer;
  late StreamController<AppCallSignal> signals;
  late StreamController<String> participants;
  late StreamController<bool> connections;
  void setupFixtures() {
    socket = _Socket();
    stream = _Stream();
    track = _Track();
    peer = _Peer();
    signals = StreamController.broadcast();
    participants = StreamController.broadcast();
    connections = StreamController.broadcast();
    when(() => socket.signalStream).thenAnswer((_) => signals.stream);
    when(() => socket.participantJoinedStream)
        .thenAnswer((_) => participants.stream);
    when(() => socket.connectionStream).thenAnswer((_) => connections.stream);
    when(() => socket.joinCall(any())).thenAnswer((_) async {});
    when(() => stream.getAudioTracks()).thenReturn([]);
    when(() => stream.getTracks()).thenReturn([track]);
    when(() => track.stop()).thenAnswer((_) async {});
    when(() => stream.dispose()).thenAnswer((_) async {});
    when(() => peer.close()).thenAnswer((_) async {});
    when(() => peer.restartIce()).thenAnswer((_) async {});
    when(() => peer.setConfiguration(any())).thenAnswer((_) async {});
    when(() => peer.setLocalDescription(any())).thenAnswer((_) async {});
    when(() => peer.setRemoteDescription(any())).thenAnswer((_) async {});
    when(() => peer.createOffer(any()))
        .thenAnswer((_) async => RTCSessionDescription('offer', 'offer'));
    when(() => peer.createAnswer(any()))
        .thenAnswer((_) async => RTCSessionDescription('answer', 'answer'));
  }

  tearDown(() async {
    await signals.close();
    await participants.close();
    await connections.close();
  });
  void finish(FakeAsync async, AppCallRtcService rtc) {
    unawaited(rtc.dispose());
    async.flushMicrotasks();
    async.elapse(Duration.zero);
  }

  test('bounds stalled ringback cleanup and never opens the microphone', () {
    fakeAsync((async) {
      setupFixtures();
      var microphoneRequested = false;
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async {
          microphoneRequested = true;
          return stream;
        },
      );
      unawaited(
        rtc
            .start(
              session: _session(),
              isCaller: true,
              prepareAudio: () => Completer<void>().future,
            )
            .catchError((Object _) {}),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(rtc.connectionState, AppCallRtcConnectionState.failed);
      expect(microphoneRequested, isFalse);
      finish(async, rtc);
    });
  });

  test('microphone stall expires at 30s and releases a late stream', () {
    fakeAsync((async) {
      setupFixtures();
      final microphone = Completer<MediaStream>();
      var completed = false;
      var peerRequested = false;
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () => microphone.future,
        createPeer: (_) async {
          peerRequested = true;
          return peer;
        },
      );
      unawaited(
        rtc
            .start(session: _session(), isCaller: true)
            .then((_) => completed = true),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 29));
      expect(rtc.connectionState, AppCallRtcConnectionState.connecting);
      async.elapse(const Duration(seconds: 1));
      expect(rtc.connectionState, AppCallRtcConnectionState.failed);
      expect(completed, isTrue);
      microphone.complete(stream);
      async.flushMicrotasks();
      verify(() => track.stop()).called(1);
      verify(() => stream.dispose()).called(1);
      expect(peerRequested, isFalse);
      finish(async, rtc);
    });
  });

  test('late peer is closed after disposal without sending an offer', () {
    fakeAsync((async) {
      setupFixtures();
      final creatingPeer = Completer<RTCPeerConnection>();
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) => creatingPeer.future,
      );
      unawaited(rtc.start(session: _session(), isCaller: true));
      async.flushMicrotasks();
      finish(async, rtc);
      creatingPeer.complete(peer);
      async.flushMicrotasks();
      verify(() => peer.close()).called(1);
      verify(() => stream.dispose()).called(1);
      verifyNever(() => peer.createOffer(any()));
    });
  });

  test('audio preparation and peer creation share the original deadline', () {
    fakeAsync((async) {
      setupFixtures();
      final preparation = Completer<void>();
      final creatingPeer = Completer<RTCPeerConnection>();
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) => creatingPeer.future,
      );
      unawaited(
        rtc.start(
          session: _session(),
          isCaller: true,
          prepareAudio: () => preparation.future,
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      preparation.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 27));
      expect(rtc.connectionState, AppCallRtcConnectionState.connecting);
      async.elapse(const Duration(seconds: 1));
      expect(rtc.connectionState, AppCallRtcConnectionState.failed);
      creatingPeer.complete(peer);
      async.flushMicrotasks();
      verify(() => peer.close()).called(1);
      verify(() => stream.dispose()).called(1);
      verifyNever(() => peer.createOffer(any()));
      finish(async, rtc);
    });
  });

  test('a stalled peer close cannot block microphone cleanup on retry', () {
    fakeAsync((async) {
      setupFixtures();
      when(() => peer.close()).thenAnswer((_) => Completer<void>().future);
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) async => peer,
      );
      unawaited(rtc.start(session: _session(), isCaller: true));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      expect(rtc.connectionState, AppCallRtcConnectionState.failed);
      finish(async, rtc);
      async.elapse(const Duration(seconds: 2));
      verify(() => track.stop()).called(1);
      verify(() => stream.dispose()).called(1);
      verify(() => peer.close()).called(1);
    });
  });

  test('recovery applies refreshed TURN before restarting ICE and offering',
      () {
    fakeAsync((async) {
      setupFixtures();
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) async => peer,
        refreshSession: (_) async => _session(relay: true),
      );
      unawaited(rtc.start(session: _session(), isCaller: true));
      async.flushMicrotasks();
      clearInteractions(peer);
      async.elapse(const Duration(seconds: 12));
      verifyInOrder([
        () => peer
            .setConfiguration({'iceServers': _session(relay: true).iceServers}),
        () => peer.restartIce(),
        () =>
            peer.createOffer({'offerToReceiveAudio': true, 'iceRestart': true}),
      ]);
      expect(rtc.connectionState, AppCallRtcConnectionState.connecting);
      peer.onConnectionState!(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      async.elapse(const Duration(seconds: 60));
      expect(rtc.connectionState, AppCallRtcConnectionState.connected);
      finish(async, rtc);
    });
  });

  test('callee applies TURN before answering a new offer', () {
    fakeAsync((async) {
      setupFixtures();
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) async => peer,
        refreshSession: (_) async => _session(relay: true),
      );
      unawaited(rtc.start(session: _session(), isCaller: false));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 12));
      signals.add(
        const AppCallSignal(
          callId: 'call-1',
          type: 'offer',
          data: {'sdp': 'restart-offer'},
        ),
      );
      async.flushMicrotasks();
      verifyInOrder([
        () => peer.setConfiguration(any()),
        () => peer.setRemoteDescription(any()),
        () => peer.createAnswer(any()),
      ]);
      finish(async, rtc);
    });
  });

  test('a refresh without TURN preserves existing relay configuration', () {
    fakeAsync((async) {
      setupFixtures();
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) async => peer,
        refreshSession: (_) async => _session(),
      );
      unawaited(rtc.start(session: _session(relay: true), isCaller: true));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 12));
      verifyNever(() => peer.setConfiguration(any()));
      verify(() => peer.restartIce()).called(1);
      finish(async, rtc);
    });
  });

  test('a refresh completing after disposal cannot configure or restart a peer',
      () {
    fakeAsync((async) {
      setupFixtures();
      final refresh = Completer<AppCallSession>();
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) async => peer,
        refreshSession: (_) => refresh.future,
      );
      unawaited(rtc.start(session: _session(), isCaller: true));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 12));
      finish(async, rtc);
      refresh.complete(_session(relay: true));
      async.flushMicrotasks();
      verifyNever(() => peer.setConfiguration(any()));
      verifyNever(() => peer.restartIce());
    });
  });

  test('a hanging refresh cannot extend the absolute connection deadline', () {
    fakeAsync((async) {
      setupFixtures();
      final refresh = Completer<AppCallSession>();
      final rtc = AppCallRtcService(
        socket: socket,
        acquireMicrophone: () async => stream,
        createPeer: (_) async => peer,
        refreshSession: (_) => refresh.future,
      );
      unawaited(rtc.start(session: _session(), isCaller: true));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      expect(rtc.connectionState, AppCallRtcConnectionState.failed);
      refresh.complete(_session(relay: true));
      async.flushMicrotasks();
      verifyNever(() => peer.setConfiguration(any()));
      verify(() => peer.restartIce()).called(1);
      finish(async, rtc);
    });
  });
}
