import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/app_lifecycle_provider.dart';
import 'package:myshop_client/src/features/services/providers/artisan_live_location_provider.dart';

class _CountingJobService extends JobService {
  _CountingJobService() : super(Dio());

  int bidLocationCalls = 0;

  @override
  Future<List<dynamic>> getBidLocations(String jobId) async {
    bidLocationCalls += 1;
    return const [];
  }
}

void main() {
  test('only resumed is treated as foreground network authority', () {
    expect(
      isForegroundLifecycleState(AppLifecycleState.resumed),
      isTrue,
    );
    for (final state in AppLifecycleState.values) {
      if (state == AppLifecycleState.resumed) continue;
      expect(
        isForegroundLifecycleState(state),
        isFalse,
        reason: '$state must pause foreground-only REST work',
      );
    }
  });

  test('live artisan REST polling does not start while backgrounded', () async {
    final service = _CountingJobService();
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.read(appForegroundedProvider.notifier).state = false;

    final subscription = container.listen(
      artisanLiveLocationsProvider('job-1'),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await pumpEventQueue();

    expect(service.bidLocationCalls, 0);

    container.read(appForegroundedProvider.notifier).state = true;
    await pumpEventQueue();
    expect(service.bidLocationCalls, 1);

    container.read(appForegroundedProvider.notifier).state = false;
    await pumpEventQueue();
    expect(service.bidLocationCalls, 1);
  });

  test('periodic REST surfaces and socket listener retain lifecycle guards',
      () {
    final guardedSources = <String>[
      'lib/src/features/activity/screens/activity_screen.dart',
      'lib/src/features/activity/providers/activity_history_provider.dart',
      'lib/src/features/services/widgets/bid_list_sheet.dart',
      'lib/src/features/services/screens/bid_detail_screen.dart',
      'lib/src/features/services/screens/job_detail_screen.dart',
      'lib/src/features/services/providers/payment_provider.dart',
      'lib/src/features/ride/providers/ride_payment_provider.dart',
    ];
    for (final path in guardedSources) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('appForegroundedProvider'),
        reason: '$path must not issue periodic REST calls in background',
      );
    }

    final socketSource =
        File('lib/src/core/providers/socket_provider.dart').readAsStringSync();
    expect(socketSource, contains('final connectionSub ='));
    expect(socketSource, contains('ref.onDispose(connectionSub.cancel);'));

    final appSource = File('lib/src/app/client_app.dart').readAsStringSync();
    expect(appSource, contains('socketServiceProvider).connect()'));
    expect(appSource, contains('socketServiceProvider).disconnect()'));
  });
}
