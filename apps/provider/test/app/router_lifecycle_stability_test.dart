import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/src/app/router.dart').readAsStringSync();
  final appSource = File('lib/src/app/provider_app.dart').readAsStringSync();
  final providerStart = source.indexOf(
    'final goRouterProvider = Provider<GoRouter>',
  );
  final providerEnd = source.indexOf(
    '/// Bridges Riverpod',
    providerStart,
  );
  final providerBody = source.substring(providerStart, providerEnd);

  test('the GoRouter instance is not recreated by redirect dependencies', () {
    expect(providerStart, greaterThanOrEqualTo(0));
    expect(providerEnd, greaterThan(providerStart));
    expect(providerBody, isNot(contains('ref.watch(')));
    expect(providerBody, contains('ref.read(authControllerProvider)'));
    expect(providerBody, contains('ref.read(legalConsentStatusProvider)'));
  });

  test('redirect dependencies refresh the stable router through listeners', () {
    final refreshBody = source.substring(providerEnd);
    expect(refreshBody, contains('_syncAuthenticatedDependencies'));
    expect(refreshBody, contains('legalConsentStatusProvider'));
    expect(refreshBody, contains('activeRideProvider.select'));
    expect(refreshBody, contains('activeJobProvider.select'));
  });

  test('service recovery is automatic, foreground-aware and single-flight', () {
    expect(
      appSource,
      contains('MobileServiceRecoveryCoordinator _serviceRecovery'),
    );
    expect(appSource, contains('probe: _probeServiceReadiness'));
    expect(
      appSource,
      contains('_queueRecoveryState(effectiveServiceIssue != null)'),
    );
    expect(
      appSource,
      contains('Future<void> _retryService() => _serviceRecovery.retryNow()'),
    );
    expect(
      appSource,
      contains('foreground: _foreground'),
    );
  });
}
