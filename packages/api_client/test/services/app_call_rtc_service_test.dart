import 'dart:async';

import 'package:api_client/src/services/app_call_rtc_service.dart';
import 'package:api_client/src/services/app_call_socket_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  group('AppCallConnectionWatchdog', () {
    test('retries once before surfacing a bounded connection failure', () {
      fakeAsync((async) {
        var retries = 0;
        var failures = 0;
        final watchdog = AppCallConnectionWatchdog(
          retryAfter: const Duration(seconds: 2),
          failAfter: const Duration(seconds: 5),
          onRetry: () => retries += 1,
          onFailure: () => failures += 1,
        )..start();

        async.elapse(const Duration(seconds: 2));
        expect(retries, 1);
        expect(failures, 0);

        async.elapse(const Duration(seconds: 3));
        expect(retries, 1);
        expect(failures, 1);

        watchdog.dispose();
      });
    });

    test('cancel prevents retry and failure callbacks', () {
      fakeAsync((async) {
        var callbacks = 0;
        final watchdog = AppCallConnectionWatchdog(
          retryAfter: const Duration(seconds: 2),
          failAfter: const Duration(seconds: 5),
          onRetry: () => callbacks += 1,
          onFailure: () => callbacks += 1,
        )
          ..start()
          ..cancel();

        async.elapse(const Duration(seconds: 10));
        expect(callbacks, 0);
        watchdog.dispose();
      });
    });
  });

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
    test('late ICE checking cannot downgrade an already connected call', () {
      expect(
        mergeAppCallRtcConnectionState(
          AppCallRtcConnectionState.connected,
          AppCallRtcConnectionState.connecting,
        ),
        AppCallRtcConnectionState.connected,
      );
    });

    test('failure is terminal for one RTC instance', () {
      expect(
        mergeAppCallRtcConnectionState(
          AppCallRtcConnectionState.failed,
          AppCallRtcConnectionState.connected,
        ),
        AppCallRtcConnectionState.failed,
      );
    });

    test('initial disconnect cannot extend the absolute watchdog deadline', () {
      expect(
        shouldRestartAppCallConnectionWatchdog(
          everConnected: false,
          state: AppCallRtcConnectionState.disconnected,
        ),
        isFalse,
      );
      expect(
        shouldRestartAppCallConnectionWatchdog(
          everConnected: true,
          state: AppCallRtcConnectionState.disconnected,
        ),
        isTrue,
      );
    });

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

  group('safe ICE diagnostics', () {
    test('counts configured STUN and TURN URLs without exposing credentials',
        () {
      final summary = appCallIceServerSummary([
        {
          'urls': [
            'stun:stun.example.com:3478',
            'turn:turn.example.com:3478?transport=udp',
          ],
          'username': 'secret-user',
          'credential': 'secret-password',
        },
        {'urls': 'turns:turn.example.com:443?transport=tcp'},
      ]);

      expect(summary.totalUrls, 3);
      expect(summary.stunUrls, 1);
      expect(summary.turnUrls, 2);
    });

    test('extracts candidate type only', () {
      expect(
        appCallIceCandidateType(
          'candidate:1 1 udp 2122260223 10.0.0.8 50000 typ host generation 0',
        ),
        'host',
      );
      expect(
        appCallIceCandidateType(
          'candidate:2 1 udp 1677734910 203.0.113.4 60000 typ srflx raddr 10.0.0.8',
        ),
        'srflx',
      );
      expect(appCallIceCandidateType(''), 'unknown');
    });
  });
}
