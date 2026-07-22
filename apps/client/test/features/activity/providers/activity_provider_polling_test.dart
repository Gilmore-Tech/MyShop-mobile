import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/activity/providers/activity_provider.dart';

class _ControlledJobService extends JobService {
  _ControlledJobService() : super(Dio());

  final firstResponse = Completer<List<dynamic>>();
  final secondResponse = Completer<List<dynamic>>();
  int calls = 0;

  @override
  Future<List<dynamic>> listJobs({
    int page = 1,
    int limit = 50,
    String? status,
    String? search,
  }) {
    calls += 1;
    return calls == 1 ? firstResponse.future : secondResponse.future;
  }
}

void main() {
  test('activity reload coalesces while the previous list request is pending',
      () async {
    final service = _ControlledJobService();
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      activityNotifierProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(Duration.zero);
    expect(service.calls, 1);

    final notifier = container.read(activityNotifierProvider.notifier);
    await notifier.silentReload();
    await notifier.reload();
    expect(service.calls, 1);

    service.firstResponse.complete(const []);
    await Future<void>.delayed(Duration.zero);
    unawaited(notifier.silentReload());
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, 2);

    service.secondResponse.complete(const []);
  });
}
