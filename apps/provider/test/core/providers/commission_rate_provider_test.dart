import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';

class _Config extends PlatformConfigService {
  _Config() : super(Dio());

  final rates = <String?, num?>{'bono': 10, 'ashanti': 20};
  final requests = <(String, String?)>[];
  bool unavailable = false;

  @override
  Future<num?> getNumber(String key, {String? regionId}) async {
    requests.add((key, regionId));
    if (unavailable) throw StateError('Unavailable');
    return rates[regionId];
  }
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
}

void main() {
  testWidgets('caches the rate without polling or refetching on screen reopen',
      (tester) async {
    final config = _Config();
    final container = ProviderContainer(overrides: [
      platformConfigServiceProvider.overrideWithValue(config),
    ]);
    final provider = commissionRatePercentProvider('bono');
    final subscription = container.listen(provider, (_, __) {});
    await _flush(tester);
    expect(container.read(provider).asData?.value, 10);

    config.rates['bono'] = 12.5;
    await tester.pump(const Duration(hours: 1));
    await _flush(tester);
    expect(container.read(provider).asData?.value, 10);
    expect(config.requests, [('commission_rate_percent', 'bono')]);

    subscription.close();
    await tester.pump();
    await tester.pump();
    final calls = config.requests.length;
    await tester.pump(const Duration(minutes: 1));
    final reopened = container.listen(provider, (_, __) {});
    await _flush(tester);
    expect(container.read(provider).asData?.value, 10);
    expect(config.requests.length, calls);
    reopened.close();
    container.dispose();
  });

  testWidgets(
      'refreshes regional caches on app resume, including a closed screen',
      (tester) async {
    final config = _Config();
    final container = ProviderContainer(overrides: [
      platformConfigServiceProvider.overrideWithValue(config),
    ]);
    final bono = commissionRatePercentProvider('bono');
    final ashanti = commissionRatePercentProvider('ashanti');
    container.listen(bono, (_, __) {});
    final ashantiSubscription = container.listen(ashanti, (_, __) {});
    await _flush(tester);
    expect(container.read(bono).asData?.value, 10);
    expect(container.read(ashanti).asData?.value, 20);

    config.rates['bono'] = 0;
    config.rates['ashanti'] = 12.5;
    ashantiSubscription.close();
    container.invalidate(commissionRatePercentProvider); // App resume.
    container.read(bono);
    await _flush(tester);
    expect(container.read(bono).asData?.value, 0);
    // Closed regions are refreshed lazily, when their estimate is next needed.
    expect(config.requests.where((call) => call.$2 == 'ashanti').length, 1);
    expect(await container.read(ashanti.future), 12.5);
    expect(config.requests.where((call) => call.$2 == 'bono').length, 2);
    expect(config.requests.where((call) => call.$2 == 'ashanti').length, 2);
    container.dispose();
  });

  testWidgets('hides the estimate on a failed refresh instead of a stale rate',
      (tester) async {
    final config = _Config();
    final container = ProviderContainer(overrides: [
      platformConfigServiceProvider.overrideWithValue(config),
    ]);
    final provider = commissionRatePercentProvider('bono');
    container.listen(provider, (_, __) {});
    await _flush(tester);
    expect(container.read(provider).asData?.value, 10);

    config.unavailable = true;
    container.invalidate(commissionRatePercentProvider);
    container.read(provider);
    await _flush(tester);
    expect(container.read(provider).hasError, isTrue);
    expect(container.read(provider).asData, isNull);
    container.dispose();
  });

  test('opening the app again starts with a fresh commission cache', () async {
    final config = _Config();
    ProviderContainer openApp() => ProviderContainer(overrides: [
          platformConfigServiceProvider.overrideWithValue(config),
        ]);
    final firstSession = openApp();
    expect(
        await firstSession.read(commissionRatePercentProvider('bono').future),
        10);
    firstSession.dispose();
    config.rates['bono'] = 12.5;
    final reopenedApp = openApp();
    expect(await reopenedApp.read(commissionRatePercentProvider('bono').future),
        12.5);
    expect(config.requests.length, 2);
    reopenedApp.dispose();
  });

  testWidgets('does not query a global rate when the job region is missing',
      (tester) async {
    final config = _Config();
    final container = ProviderContainer(overrides: [
      platformConfigServiceProvider.overrideWithValue(config),
    ]);
    final provider = commissionRatePercentProvider('');
    container.listen(provider, (_, __) {});
    await _flush(tester);
    expect(container.read(provider).hasError, isTrue);
    expect(config.requests, isEmpty);
    container.dispose();
  });
}
