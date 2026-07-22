import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/services/providers/bid_list_provider.dart';
import 'package:myshop_client/src/features/services/providers/job_data_refresh_coordinator.dart';
import 'package:myshop_client/src/features/services/providers/job_detail_provider.dart';

class _ControlledJobService extends JobService {
  _ControlledJobService() : super(Dio());

  final jobResponses = <Completer<Map<String, dynamic>>>[
    Completer<Map<String, dynamic>>(),
    Completer<Map<String, dynamic>>(),
  ];
  final bidResponses = <Completer<List<dynamic>>>[
    Completer<List<dynamic>>(),
    Completer<List<dynamic>>(),
  ];
  int jobCalls = 0;
  int bidCalls = 0;

  @override
  Future<Map<String, dynamic>> getJob(String jobId) {
    final response = jobResponses[jobCalls];
    jobCalls += 1;
    return response.future;
  }

  @override
  Future<List<dynamic>> getBids(String jobId) {
    final response = bidResponses[bidCalls];
    bidCalls += 1;
    return response.future;
  }
}

void main() {
  test('job and bid refreshes join initial loads and each other', () async {
    final service = _ControlledJobService();
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final jobSub = container.listen(
      jobDetailProvider('job-1'),
      (_, __) {},
      fireImmediately: true,
    );
    final bidSub = container.listen(
      bidsForJobProvider('job-1'),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(jobSub.close);
    addTearDown(bidSub.close);
    await Future<void>.delayed(Duration.zero);

    final coordinator = container.read(jobDataRefreshCoordinatorProvider);
    final first = coordinator.refreshJobAndBids('job-1');
    final duplicate = coordinator.refreshJobAndBids('job-1');
    await Future<void>.delayed(Duration.zero);
    expect(service.jobCalls, 1);
    expect(service.bidCalls, 1);

    service.jobResponses[0].complete(_jobJson());
    service.bidResponses[0].complete(const []);
    await Future.wait([first, duplicate]);

    final next = coordinator.refreshJobAndBids('job-1');
    final nextDuplicate = coordinator.refreshJobAndBids('job-1');
    await Future<void>.delayed(Duration.zero);
    expect(service.jobCalls, 2);
    expect(service.bidCalls, 2);

    service.jobResponses[1].complete(_jobJson());
    service.bidResponses[1].complete(const []);
    await Future.wait([next, nextDuplicate]);
  });

  test('a failed background refresh releases the fence for retry', () async {
    final service = _ControlledJobService();
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final jobSub = container.listen(
      jobDetailProvider('job-1'),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(jobSub.close);
    await Future<void>.delayed(Duration.zero);

    final coordinator = container.read(jobDataRefreshCoordinatorProvider);
    final failed = coordinator.refreshJob('job-1');
    service.jobResponses[0].completeError(Exception('network unavailable'));
    await expectLater(failed, completes);

    final retry = coordinator.refreshJob('job-1');
    await Future<void>.delayed(Duration.zero);
    expect(service.jobCalls, 2);
    service.jobResponses[1].complete(_jobJson());
    await retry;
  });
}

Map<String, dynamic> _jobJson() => {
      'id': 'job-1',
      'status': 'open',
      'description': 'Repair a socket',
      'addressText': 'Kumasi',
      'latitude': 6.6885,
      'longitude': -1.6244,
      'createdAt': '2026-07-22T00:00:00.000Z',
      'category': {'name': 'Electrical'},
      'bids': const [],
    };
