import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/services/providers/active_job_provider.dart';
import 'package:myshop_client/src/features/services/providers/bid_list_provider.dart';
import 'package:myshop_client/src/features/services/providers/job_form_provider.dart';

void main() {
  test('unexpected active-job failure is not treated as success', () async {
    final notifier = ActiveJobNotifier(
      _ThrowingJobService(StateError('internal transport detail')),
    );
    addTearDown(notifier.dispose);

    await notifier.confirmArrival(jobId: 'job-1');

    expect(notifier.state.isConfirmingArrival, isFalse);
    expect(
      notifier.state.errorMessage,
      "Couldn't confirm the job update. Please try again.",
    );
  });

  test('active-job API failure hides arbitrary backend prose', () async {
    final notifier = ActiveJobNotifier(
      _ThrowingJobService(
        const ApiException(
          message: 'SQLSTATE 23505 internal job owner index',
          statusCode: 400,
          errorCode: 'UNRECOGNISED_JOB_FAILURE',
        ),
      ),
    );
    addTearDown(notifier.dispose);

    await notifier.markComplete(jobId: 'job-1');

    expect(notifier.state.errorMessage, isNot(contains('SQLSTATE')));
    expect(notifier.state.errorMessage, contains("Couldn't confirm"));
  });

  test('unexpected bid selection failure remains visible as a failure',
      () async {
    final notifier = BidListNotifier(
      _MockRef(),
      _ThrowingJobService(StateError('decoder failed')),
    );
    addTearDown(notifier.dispose);

    await notifier.selectBid(jobId: 'job-1', bidId: 'bid-1');

    expect(notifier.state.isSelecting, isFalse);
    expect(
      notifier.state.errorMessage,
      'Failed to accept the bid. Please try again.',
    );
  });

  test('job request cannot submit with a typed address but no coordinates', () {
    const state = JobFormState(
      selectedCategoryId: 'category-1',
      title: 'Repair socket',
      description: 'The wall socket is damaged',
      destinationAddress: 'Typed address without a selected map result',
    );

    expect(state.canSubmit, isFalse);
  });
}

class _MockRef extends Mock implements Ref {}

class _ThrowingJobService extends JobService {
  _ThrowingJobService(this.error) : super(Dio());

  final Object error;

  Never _throw() => throw error;

  @override
  Future<Map<String, dynamic>> confirmJobCompletion(String jobId) async =>
      _throw();

  @override
  Future<Map<String, dynamic>> selectBid(
    String jobId, {
    required String bidId,
  }) async =>
      _throw();
}
