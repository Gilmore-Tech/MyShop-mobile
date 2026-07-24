import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repositoryRoot = Directory('../..');

  String read(String relativePath) =>
      File('${repositoryRoot.path}/$relativePath').readAsStringSync();

  test('mobile dependencies contain no unapproved crash or analytics SDK', () {
    final dependencyFiles = <String>[
      'apps/client/pubspec.yaml',
      'apps/provider/pubspec.yaml',
      'apps/client/ios/Podfile.lock',
      'apps/provider/ios/Podfile.lock',
      'apps/client/android/app/build.gradle.kts',
      'apps/provider/android/app/build.gradle.kts',
    ];
    final forbiddenDependencies = <RegExp>[
      RegExp(r'\bfirebase_crashlytics\b', caseSensitive: false),
      RegExp(r'\bfirebase_analytics\b', caseSensitive: false),
      RegExp(r'\bsentry_flutter\b', caseSensitive: false),
      RegExp(r'\bbugsnag_flutter\b', caseSensitive: false),
      RegExp(r'\bdatadog_flutter_plugin\b', caseSensitive: false),
      RegExp(r'\bnewrelic_mobile\b', caseSensitive: false),
      RegExp(r'\binstabug_flutter\b', caseSensitive: false),
      RegExp(r'\bappcenter_analytics\b', caseSensitive: false),
      RegExp(r'\bappcenter_crashes\b', caseSensitive: false),
    ];

    for (final relativePath in dependencyFiles) {
      final source = read(relativePath);
      for (final forbidden in forbiddenDependencies) {
        expect(
          source,
          isNot(matches(forbidden)),
          reason:
              '$relativePath enables telemetry that has no approved privacy policy',
        );
      }
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'implementation\s*\([^)]*(?:firebase-analytics|firebase-crashlytics)',
              caseSensitive: false,
            ),
          ),
        ),
        reason: '$relativePath directly enables Firebase telemetry',
      );
    }
  });

  test('Firebase configuration keeps product analytics disabled', () {
    final disabledAnalytics = RegExp(
      r'<key>IS_ANALYTICS_ENABLED</key>\s*<false(?:\s*/>|>\s*</false>)',
    );
    for (final relativePath in <String>[
      'apps/client/ios/Runner/GoogleService-Info.plist',
      'apps/provider/ios/Runner/GoogleService-Info.plist',
    ]) {
      expect(
        read(relativePath),
        matches(disabledAnalytics),
        reason: '$relativePath must not silently enable Firebase Analytics',
      );
    }
  });

  test('app privacy manifests describe the shipped no-crash-SDK state', () {
    for (final relativePath in <String>[
      'apps/client/ios/Runner/PrivacyInfo.xcprivacy',
      'apps/provider/ios/Runner/PrivacyInfo.xcprivacy',
    ]) {
      final source = read(relativePath);
      expect(
        source,
        isNot(contains('NSPrivacyCollectedDataTypeCrashData')),
        reason: '$relativePath declares crash collection without a crash SDK',
      );
      expect(
        source,
        isNot(matches(RegExp(r'Crashlytics', caseSensitive: false))),
        reason: '$relativePath refers to an SDK that is not shipped',
      );
      expect(
        source,
        matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false\s*/>')),
        reason: '$relativePath must keep cross-app tracking disabled',
      );
    }
  });

  test('repository tooling config never embeds a GitHub credential', () {
    final source = read('.claude/mcp/mcp-config.json');
    final config = jsonDecode(source) as Map<String, dynamic>;
    final servers = config['mcpServers'] as Map<String, dynamic>;
    final github = servers['github'] as Map<String, dynamic>;

    expect(github.containsKey('env'), isFalse,
        reason:
            'MCP processes must inherit credentials from the host environment');
    expect(
      source,
      isNot(matches(RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'))),
      reason: 'a GitHub credential is committed in the mobile repository',
    );
  });
}
