import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';
import 'package:myshop_provider/src/features/artisan_home/providers/job_poller_provider.dart';

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
  test('artisan fallback poller never overlaps a slow list request', () async {
    final service = _ControlledJobService();
    final container = ProviderContainer(
      overrides: [
        jobServiceProvider.overrideWithValue(service),
        jobPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(providerStatusProvider.notifier).goOnline();
    container.read(jobPollerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.calls, 1);

    service.firstResponse.complete(const []);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(service.calls, 2);

    service.secondResponse.complete(const []);
  });
}
