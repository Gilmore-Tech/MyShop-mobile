import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(Directory directory) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains(
          '${Platform.pathSeparator}test${Platform.pathSeparator}',
        ) ||
        entity.path.endsWith('.g.dart') ||
        entity.path.endsWith('.freezed.dart')) {
      continue;
    }
    yield entity;
  }
}

void main() {
  final repositoryRoot = Directory('../..');
  final productionRoots = <Directory>[
    Directory('lib'),
    Directory('../shared_models/lib'),
    Directory('../shared_ui/lib'),
    Directory('../../apps/client/lib'),
    Directory('../../apps/provider/lib'),
  ];

  test('non-debug artifacts install a fail-closed diagnostic boundary', () {
    final boundary = File('lib/mobile_diagnostics.dart').readAsStringSync();

    expect(boundary, contains('if (!kDebugMode)'));
    expect(boundary, contains('debugPrint = _discardDiagnostic;'));
    expect(boundary, contains('if (!kDebugMode) return;'));
    expect(boundary, contains('String Function() message'));
    expect(boundary, contains('message()'));

    for (final relativePath in <String>[
      'apps/client/lib/main.dart',
      'apps/provider/lib/main.dart',
    ]) {
      final source =
          File('${repositoryRoot.path}/$relativePath').readAsStringSync();
      final install = source.indexOf('installMobileProductionLogPolicy();');
      final firstDiagnostic = source.indexOf('debugLog(() =>');
      expect(install, greaterThanOrEqualTo(0), reason: relativePath);
      expect(firstDiagnostic, greaterThan(install), reason: relativePath);
    }
  });

  test('background push isolates install the policy before diagnostics', () {
    for (final relativePath in <String>[
      'apps/client/lib/src/core/services/fcm_service.dart',
      'apps/provider/lib/src/core/services/fcm_service.dart',
    ]) {
      final source =
          File('${repositoryRoot.path}/$relativePath').readAsStringSync();
      expect(
        source,
        matches(
          RegExp(
            r'Future<void> fcmBackgroundHandler\(RemoteMessage message\) async \{\s*'
            r'installMobileProductionLogPolicy\(\);',
          ),
        ),
        reason: relativePath,
      );
    }
  });

  test('production libraries cannot bypass the shared boundary', () {
    final directDeveloperImport = RegExp(
      r'''import\s+['"]dart:developer['"]''',
    );
    final directDeveloperLog = RegExp(r'\bdeveloper\.log\s*\(');
    final directDebugPrint = RegExp(r'\bdebugPrint\s*\(');
    final directPrint = RegExp(r'\bprint\s*\(');

    for (final root in productionRoots) {
      for (final file in _dartFiles(root)) {
        final source = file.readAsStringSync();
        final isBoundary = file.absolute.path ==
            File('lib/mobile_diagnostics.dart').absolute.path;
        if (!isBoundary) {
          expect(
            source,
            isNot(matches(directDeveloperImport)),
            reason: '${file.path} imports dart:developer directly',
          );
          expect(
            source,
            isNot(matches(directDeveloperLog)),
            reason: '${file.path} bypasses the lazy developer-log boundary',
          );
        }
        expect(
          source,
          isNot(matches(directDebugPrint)),
          reason: '${file.path} constructs a diagnostic before the debug gate',
        );
        expect(
          source,
          isNot(matches(directPrint)),
          reason: '${file.path} uses print() outside the diagnostic boundary',
        );
        if (source.contains('debugLog(() =>')) {
          expect(
            source,
            contains("package:api_client/mobile_diagnostics.dart'"),
            reason: '${file.path} uses debugLog without the shared boundary',
          );
        }
      }
    }
  });

  test('app-owned native diagnostics are debug-only and identifier-free', () {
    for (final relativePath in <String>[
      'apps/client/ios/Runner/AppDelegate.swift',
      'apps/provider/ios/Runner/AppDelegate.swift',
    ]) {
      final source =
          File('${repositoryRoot.path}/$relativePath').readAsStringSync();
      expect(source, contains('#if DEBUG'), reason: relativePath);
      expect(
        RegExp(r'\bNSLog\s*\(').allMatches(source),
        hasLength(1),
        reason: '$relativePath may call NSLog only inside mobileDebugLog',
      );
      for (final line in source.split('\n')) {
        if (!line.contains('mobileDebugLog(') ||
            line.contains('private func mobileDebugLog')) {
          continue;
        }
        expect(
          line,
          isNot(contains(r'\(')),
          reason: '$relativePath native log interpolates a private value',
        );
      }
    }

    for (final root in <Directory>[
      Directory('../../apps/client/android/app/src/main'),
      Directory('../../apps/provider/android/app/src/main'),
      Directory('../../packages/incoming_request_overlay/android/src/main'),
    ]) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File ||
            !(entity.path.endsWith('.kt') || entity.path.endsWith('.java')) ||
            entity.path.endsWith('GeneratedPluginRegistrant.java')) {
          continue;
        }
        final source = entity.readAsStringSync();
        expect(
          source,
          isNot(
            matches(
              RegExp(
                r'\b(?:Log\.(?:v|d|i|w|e|wtf)|println|System\.out\.print)\s*\(',
              ),
            ),
          ),
          reason: '${entity.path} bypasses the mobile diagnostic policy',
        );
      }
    }
  });
}
