import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _providerRoot() {
  final current = Directory.current;
  final nested = Directory('${current.path}/apps/provider');
  if (File('${nested.path}/pubspec.yaml').existsSync()) return nested;
  if (File('${current.path}/pubspec.yaml').existsSync()) return current;
  throw StateError('Could not locate the provider package root');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all packaged MP3 request sounds match the canonical Flutter asset',
      () async {
    final provider = _providerRoot();
    final repository = provider.parent.parent;
    final canonical = await File(
      '${provider.path}/assets/audio/incoming_request.mp3',
    ).readAsBytes();

    expect(canonical, isNotEmpty);
    expect(
      await File(
        '${provider.path}/android/app/src/main/res/raw/incoming_request.mp3',
      ).readAsBytes(),
      canonical,
    );
    expect(
      await File(
        '${repository.path}/packages/incoming_request_overlay/android/src/main/res/raw/incoming_request.mp3',
      ).readAsBytes(),
      canonical,
    );
    expect(
      await File(
        '${provider.path}/ios/Runner/Sounds/incoming_request.mp3',
      ).readAsBytes(),
      canonical,
    );

    final bundled = await rootBundle.load('assets/audio/incoming_request.mp3');
    expect(bundled.buffer.asUint8List(), canonical);
  });

  test('iOS request notification sound is a non-empty CAF file', () async {
    final provider = _providerRoot();
    final caf = await File(
      '${provider.path}/ios/Runner/Sounds/incoming_request.caf',
    ).readAsBytes();

    expect(caf.length, greaterThan(4));
    expect(Uint8List.sublistView(caf, 0, 4), <int>[0x63, 0x61, 0x66, 0x66]);
  });
}
