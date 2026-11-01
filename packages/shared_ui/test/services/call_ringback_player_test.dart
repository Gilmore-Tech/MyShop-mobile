import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/src/services/call_ringback_player.dart';

class _Player implements AudioPlayer {
  final contextReady = Completer<void>();
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  final stopped = Completer<void>();

  @override
  Future<void> setAudioContext(AudioContext context) => contextReady.future;
  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {}
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playCount++;
  }

  @override
  Future<void> stop() {
    stopCount++;
    return stopped.future;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('stop cancels unfinished startup and prevents late ringback playback',
      () async {
    final player = _Player();
    final ringback = CallRingbackPlayer(createPlayer: () => player);
    final starting = ringback.start();
    final stopping = ringback.stop();
    expect(player.stopCount, 1);
    expect(ringback.isPlaying, isFalse);
    player.stopped.complete();
    await stopping;
    expect(player.disposeCount, 1);
    player.contextReady.complete();
    await starting;
    expect(player.playCount, 0);
  });

  test('concurrent stops share cleanup until native stop finishes', () async {
    final player = _Player();
    final ringback = CallRingbackPlayer(createPlayer: () => player);
    final starting = ringback.start();
    player.contextReady.complete();
    await starting;
    expect(player.playCount, 1);
    final first = ringback.stop();
    final second = ringback.stop();
    expect(identical(first, second), isTrue);
    expect(player.disposeCount, 0);
    player.stopped.complete();
    await Future.wait([first, second]);
    expect(player.stopCount, 1);
    expect(player.disposeCount, 1);
  });
}
