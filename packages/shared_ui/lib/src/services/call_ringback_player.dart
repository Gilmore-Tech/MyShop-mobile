import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a familiar call-progress tone while an outgoing call is ringing.
///
/// The WAV is generated in memory so both MyShop apps share the same cadence
/// without carrying another platform-specific audio asset. The player is
/// stopped before WebRTC starts, so it cannot retain audio focus once the call
/// is connected.
class CallRingbackPlayer {
  AudioPlayer? _player;
  Future<void>? _starting;

  bool get isPlaying => _player != null;

  Future<void> start() {
    if (_player != null) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    if (_player != null) return;
    final player = AudioPlayer();
    _player = player;
    try {
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.voiceCommunicationSignalling,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const {AVAudioSessionOptions.allowBluetooth},
          ),
        ),
      );
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(
        BytesSource(_ringbackWav, mimeType: 'audio/wav'),
        volume: 0.42,
      );
    } catch (error) {
      debugPrint('[CALL-AUDIO] ringback start failed: $error');
      if (identical(_player, player)) _player = null;
      await player.dispose();
    }
  }

  Future<void> stop() async {
    await _starting;
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (error) {
      debugPrint('[CALL-AUDIO] ringback stop failed: $error');
    } finally {
      await player.dispose();
    }
  }
}

final Uint8List _ringbackWav = _buildRingbackWav();

/// 425 Hz, one second on and three seconds off. This is the standard
/// call-progress cadence used by many GSM networks, including the tone most
/// callers in Ghana will recognise as "ringing".
Uint8List _buildRingbackWav() {
  const sampleRate = 8000;
  const durationSeconds = 4;
  const toneSeconds = 1;
  const bytesPerSample = 2;
  const sampleCount = sampleRate * durationSeconds;
  const dataLength = sampleCount * bytesPerSample;

  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.view(bytes.buffer);

  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * bytesPerSample, Endian.little);
  data.setUint16(32, bytesPerSample, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);

  const attackReleaseSamples = sampleRate ~/ 50;
  for (var sample = 0; sample < sampleCount; sample++) {
    var value = 0.0;
    if (sample < sampleRate * toneSeconds) {
      final withinTone = sample;
      final remaining = sampleRate * toneSeconds - withinTone;
      final envelope = math.min(
        1.0,
        math.min(withinTone, remaining) / attackReleaseSamples,
      );
      value =
          math.sin(2 * math.pi * 425 * sample / sampleRate) * 0.34 * envelope;
    }
    data.setInt16(
      44 + sample * bytesPerSample,
      (value * 32767).round(),
      Endian.little,
    );
  }
  return bytes;
}
