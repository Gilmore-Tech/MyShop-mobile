import 'dart:async';

import 'package:api_client/src/services/app_call_rtc_service.dart';
import 'package:api_client/src/services/app_call_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  group('AppCallSignalSerialQueue', () {
    AppCallSignal signal(String type) => AppCallSignal(
          callId: 'call-1',
          type: type,
          data: const <String, dynamic>{},
        );

    test('retains pre-peer signals and drains them in arrival order', () async {
      final handled = <String>[];
      final queue = AppCallSignalSerialQueue();

      queue
        ..add(signal('offer'), (value) async => handled.add(value.type))
        ..add(signal('ice'), (value) async => handled.add(value.type));

      expect(queue.pendingCount, 2);
      expect(handled, isEmpty);

      await queue.markReady((value) async => handled.add(value.type));

      expect(queue.pendingCount, 0);
      expect(handled, <String>['offer', 'ice']);
    });

    test('serialises asynchronous handlers after becoming ready', () async {
      final handled = <String>[];
      final firstMayFinish = Completer<void>();
      final queue = AppCallSignalSerialQueue();
      await queue.markReady((_) async {});

      queue.add(signal('offer'), (value) async {
        handled.add('${value.type}:start');
        await firstMayFinish.future;
        handled.add('${value.type}:end');
      });
      queue.add(signal('ice'), (value) async {
        handled.add(value.type);
      });

      await Future<void>.delayed(Duration.zero);
      expect(handled, <String>['offer:start']);

      firstMayFinish.complete();
      await queue.drain();
      expect(handled, <String>['offer:start', 'offer:end', 'ice']);
    });

    test('continues after a handler failure', () async {
      final errors = <Object>[];
      final handled = <String>[];
      final queue = AppCallSignalSerialQueue(
        onError: (error, _) => errors.add(error),
      );
      await queue.markReady((_) async {});

      queue.add(signal('offer'), (_) async => throw StateError('bad offer'));
      queue.add(signal('answer'), (value) async => handled.add(value.type));
      await queue.drain();

      expect(errors, hasLength(1));
      expect(handled, <String>['answer']);
    });

    test('drops pending and subsequent signals after dispose', () async {
      final handled = <String>[];
      final queue = AppCallSignalSerialQueue();
      queue.add(signal('offer'), (value) async => handled.add(value.type));

      queue.dispose();
      await queue.markReady((value) async => handled.add(value.type));
      queue.add(signal('ice'), (value) async => handled.add(value.type));
      await queue.drain();

      expect(queue.pendingCount, 0);
      expect(handled, isEmpty);
    });
  });

  group('AppCallRtcConnectionState mapping', () {
    test('maps peer connection states for UI', () {
      expect(
        appCallRtcStateFromPeerState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting,
        ),
        AppCallRtcConnectionState.connecting,
      );
      expect(
        appCallRtcStateFromPeerState(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        ),
        AppCallRtcConnectionState.connected,
      );
      expect(
        appCallRtcStateFromPeerState(
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
        ),
        AppCallRtcConnectionState.disconnected,
      );
      expect(
        appCallRtcStateFromPeerState(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        ),
        AppCallRtcConnectionState.failed,
      );
    });

    test('maps ICE connection states for UI', () {
      expect(
        appCallRtcStateFromIceState(
          RTCIceConnectionState.RTCIceConnectionStateChecking,
        ),
        AppCallRtcConnectionState.connecting,
      );
      expect(
        appCallRtcStateFromIceState(
          RTCIceConnectionState.RTCIceConnectionStateCompleted,
        ),
        AppCallRtcConnectionState.connected,
      );
      expect(
        appCallRtcStateFromIceState(
          RTCIceConnectionState.RTCIceConnectionStateDisconnected,
        ),
        AppCallRtcConnectionState.disconnected,
      );
      expect(
        appCallRtcStateFromIceState(
          RTCIceConnectionState.RTCIceConnectionStateFailed,
        ),
        AppCallRtcConnectionState.failed,
      );
    });
  });
}
