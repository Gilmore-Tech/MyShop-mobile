import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/artisan_home/providers/active_job_provider.dart';
import 'package:shared_models/shared_models.dart';

class _FakeJobService extends JobService {
  _FakeJobService() : super(Dio());

  Map<String, dynamic> statusResponse = const <String, dynamic>{};
  Map<String, dynamic> cashResponse = const <String, dynamic>{};
  late Map<String, dynamic> jobResponse;
  int getCalls = 0;

  @override
  Future<Map<String, dynamic>> updateJobStatus(
    String jobId, {
    required String status,
    double? currentLat,
    double? currentLng,
    double? accuracyMeters,
    DateTime? capturedAt,
  }) async {
    return statusResponse;
  }

  @override
  Future<Map<String, dynamic>> getJob(String jobId) async {
    getCalls++;
    return jobResponse;
  }

  @override
  Future<Map<String, dynamic>> artisanConfirmCash(String jobId) async {
    return cashResponse;
  }
}

class _ControlledRefreshJobService extends JobService {
  _ControlledRefreshJobService() : super(Dio());

  final response = Completer<Map<String, dynamic>>();
  int getCalls = 0;

  @override
  Future<Map<String, dynamic>> getJob(String jobId) {
    getCalls += 1;
    return response.future;
  }
}

Job _job(
  JobStatus status, {
  String? clientPhone = '+233241234567',
}) =>
    Job(
      id: 'job-1',
      status: status,
      categoryId: 'category-1',
      categoryName: 'Repairs',
      description: 'Repair a door',
      latitude: 5.6037,
      longitude: -0.1870,
      clientName: 'Client One',
      clientPhone: clientPhone,
      clientPhotoUrl: 'https://example.test/client.jpg',
    );

Map<String, dynamic> _jobJson(String status) => {
      'id': 'job-1',
      'status': status,
      'categoryId': 'category-1',
      'categoryName': 'Repairs',
      'description': 'Repair a door',
      'latitude': 5.6037,
      'longitude': -0.1870,
      'clientName': 'Client One',
      'clientPhone': '+233241234567',
      'clientPhotoUrl': 'https://example.test/client.jpg',
    };

void main() {
  test('active-job acknowledgement refreshes share one pending REST read',
      () async {
    final service = _ControlledRefreshJobService();
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeJobProvider.notifier);
    notifier.setJob(_job(JobStatus.artisanMarkedComplete));

    final first = notifier.refreshFromServer();
    final second = notifier.refreshFromServer();
    await Future<void>.delayed(Duration.zero);

    expect(service.getCalls, 1);

    service.response.complete(_jobJson('artisan_marked_complete'));
    await Future.wait([first, second]);
  });

  test('hydrates a missing client phone so both call choices are available',
      () async {
    final service = _FakeJobService()
      ..jobResponse = {
        ..._jobJson('confirmed'),
        'clientPhone': '+233501234567',
      };
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    container
        .read(activeJobProvider.notifier)
        .setJob(_job(JobStatus.confirmed, clientPhone: null));
    await Future<void>.delayed(Duration.zero);

    expect(service.getCalls, 1);
    expect(
      container.read(activeJobProvider).job?.clientPhone,
      '+233501234567',
    );
  });

  test('malformed acknowledgement does not invent an artisan job status',
      () async {
    final service = _FakeJobService()
      ..statusResponse = const <String, dynamic>{}
      ..jobResponse = _jobJson('confirmed');
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeJobProvider.notifier);
    notifier.setJob(_job(JobStatus.confirmed));

    final updated = await notifier.startEnRoute();

    expect(updated, isFalse);
    expect(container.read(activeJobProvider).job?.status, JobStatus.confirmed);
    expect(
      container.read(activeJobProvider).errorMessage,
      contains("couldn't confirm"),
    );
  });

  test('read-back may confirm a committed artisan lifecycle transition',
      () async {
    final service = _FakeJobService()
      ..statusResponse = const <String, dynamic>{}
      ..jobResponse = _jobJson('artisan_en_route');
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeJobProvider.notifier);
    notifier.setJob(_job(JobStatus.confirmed));

    final updated = await notifier.startEnRoute();

    expect(updated, isTrue);
    expect(
      container.read(activeJobProvider).job?.status,
      JobStatus.artisanEnRoute,
    );
  });

  test('exact acknowledgement advances without an unnecessary read-back',
      () async {
    final service = _FakeJobService()
      ..statusResponse = const <String, dynamic>{
        'jobId': 'job-1',
        'status': 'artisan_en_route',
      }
      ..jobResponse = _jobJson('confirmed');
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeJobProvider.notifier);
    notifier.setJob(_job(JobStatus.confirmed));

    final updated = await notifier.startEnRoute();

    expect(updated, isTrue);
    expect(service.getCalls, 0);
    expect(
      container.read(activeJobProvider).job?.status,
      JobStatus.artisanEnRoute,
    );
  });

  test('cash confirmation does not invent completion from malformed data',
      () async {
    final service = _FakeJobService()
      ..cashResponse = const <String, dynamic>{}
      ..jobResponse = _jobJson('artisan_marked_complete');
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeJobProvider.notifier);
    notifier.setJob(_job(JobStatus.artisanMarkedComplete));

    final completed = await notifier.confirmCashReceipt();

    expect(completed, isFalse);
    expect(
      container.read(activeJobProvider).job?.status,
      JobStatus.artisanMarkedComplete,
    );
    expect(
      container.read(activeJobProvider).errorMessage,
      contains("couldn't confirm"),
    );
  });

  test('cash completion read-back recovers a committed response loss',
      () async {
    final service = _FakeJobService()
      ..cashResponse = const <String, dynamic>{}
      ..jobResponse = _jobJson('completed');
    final container = ProviderContainer(
      overrides: [jobServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeJobProvider.notifier);
    notifier.setJob(_job(JobStatus.artisanMarkedComplete));

    final completed = await notifier.confirmCashReceipt();

    expect(completed, isTrue);
    expect(container.read(activeJobProvider).job?.status, JobStatus.completed);
  });
}
