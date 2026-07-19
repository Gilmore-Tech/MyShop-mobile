import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/services/data/job_cancellation_coordinator.dart';

class _MockJobService extends Mock implements JobService {}

void main() {
  late _MockJobService jobService;

  setUp(() {
    jobService = _MockJobService();
  });

  test('accepts a successful job cancellation without read-back', () async {
    when(() => jobService.cancelJob('job-1', reason: 'client_cancelled'))
        .thenAnswer(
      (_) async => <String, dynamic>{
        'jobId': 'job-1',
        'cancellationFeePesewas': 0,
      },
    );

    final result = await cancelJobWithAuthority(
      jobService: jobService,
      jobId: 'job-1',
      reason: 'client_cancelled',
    );

    expect(result.confirmedCancelled, isTrue);
    expect(result.reconciled, isFalse);
    verifyNever(() => jobService.getJob(any()));
  });

  test('recognises job cancellation after an ambiguous timeout', () async {
    when(() => jobService.cancelJob('job-1', reason: 'client_cancelled'))
        .thenThrow(const NetworkException(message: 'timeout'));
    when(() => jobService.getJob('job-1')).thenAnswer(
      (_) async => <String, dynamic>{'id': 'job-1', 'status': 'cancelled'},
    );

    final result = await cancelJobWithAuthority(
      jobService: jobService,
      jobId: 'job-1',
      reason: 'client_cancelled',
    );

    expect(result.confirmedCancelled, isTrue);
    expect(result.reconciled, isTrue);
  });

  test('preserves an active job and hides raw backend prose', () async {
    when(() => jobService.cancelJob('job-1', reason: 'client_cancelled'))
        .thenThrow(
      const ApiException(
        message: 'raw backend job detail',
        statusCode: 400,
        errorCode: 'JOB_NOT_CANCELLABLE',
      ),
    );
    when(() => jobService.getJob('job-1')).thenAnswer(
      (_) async => <String, dynamic>{'id': 'job-1', 'status': 'in_progress'},
    );

    final result = await cancelJobWithAuthority(
      jobService: jobService,
      jobId: 'job-1',
      reason: 'client_cancelled',
    );

    expect(result.confirmedCancelled, isFalse);
    expect(result.message, contains('already started'));
    expect(result.message, isNot(contains('raw backend')));
  });

  test('keeps the job open when read-back is unavailable', () async {
    when(() => jobService.cancelJob('job-1', reason: 'client_cancelled'))
        .thenThrow(const NetworkException(message: 'timeout'));
    when(() => jobService.getJob('job-1'))
        .thenThrow(const NetworkException(message: 'still offline'));

    final result = await cancelJobWithAuthority(
      jobService: jobService,
      jobId: 'job-1',
      reason: 'client_cancelled',
    );

    expect(result.confirmedCancelled, isFalse);
    expect(result.reconciled, isFalse);
    expect(result.message, contains("couldn't confirm"));
  });
}
