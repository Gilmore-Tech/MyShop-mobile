import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/logout_cleanup_bridge.dart';
import 'package:myshop_provider/src/core/providers/socket_provider.dart';
import 'package:myshop_provider/src/core/services/job_offer_receipt_service.dart';
import 'package:myshop_provider/src/features/artisan_home/providers/job_poller_provider.dart';
import 'package:myshop_provider/src/features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const jobId = '11111111-1111-4111-8111-111111111111';
  const offerId = '22222222-2222-4222-8222-222222222222';
  const legacyJobId = '33333333-3333-4333-8333-333333333333';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetJobOfferReceiptMemoryForTesting();
  });

  test('account switch purges every job-offer identity and UI surface',
      () async {
    final clearedAlerts = <String, String?>{};
    var ringtoneStopped = false;
    final container = ProviderContainer(
      overrides: [
        jobRequestAlertCleanupProvider.overrideWithValue(({
          required String jobId,
          String? offerId,
        }) async {
          clearedAlerts[jobId] = offerId;
        }),
        incomingRequestRingtoneTeardownProvider.overrideWithValue(() async {
          ringtoneStopped = true;
        }),
      ],
    );
    addTearDown(container.dispose);
    const job = Job(
      id: jobId,
      status: JobStatus.open,
      categoryId: 'plumbing',
      description: 'Repair a tap',
      latitude: 5.6,
      longitude: -0.2,
    );
    const legacyJob = Job(
      id: legacyJobId,
      status: JobStatus.open,
      categoryId: 'electrical',
      description: 'Legacy request',
      latitude: 5.6,
      longitude: -0.2,
    );
    await persistIncomingJobOffer(const {
      'jobId': jobId,
      'offerId': offerId,
      'offerVersion': 2,
    });
    container.read(surfacedJobIdsProvider.notifier).state = {jobId};
    container.read(incomingJobRequestProvider.notifier).state = job;
    container.read(visibleJobRequestIdProvider.notifier).state = jobId;
    container.read(visibleJobModalIdProvider.notifier).state = jobId;
    container.read(jobOfferIdByJobProvider.notifier).state = {
      jobId: offerId,
    };
    container.read(lastJobOfferIdByJobProvider.notifier).state = {
      jobId: offerId,
    };
    container.read(jobOfferDeadlineByJobProvider.notifier).state = {
      jobId: DateTime.now().toUtc().add(const Duration(seconds: 45)),
    };
    container.read(jobOfferDismissalProvider.notifier).state =
        const JobOfferDismissal(jobId: jobId, reason: 'test', offerId: offerId);
    container.read(pendingIncomingJobsProvider.notifier).enqueue(job);
    container.read(pendingIncomingJobsProvider.notifier).enqueue(legacyJob);

    await container.read(jobOfferSessionCleanupProvider)();

    expect(container.read(surfacedJobIdsProvider), isEmpty);
    expect(container.read(incomingJobRequestProvider), isNull);
    expect(container.read(visibleJobRequestIdProvider), isNull);
    expect(container.read(visibleJobModalIdProvider), isNull);
    expect(container.read(jobOfferIdByJobProvider), isEmpty);
    expect(container.read(lastJobOfferIdByJobProvider), isEmpty);
    expect(container.read(jobOfferDeadlineByJobProvider), isEmpty);
    expect(container.read(jobOfferDismissalProvider), isNull);
    expect(container.read(pendingIncomingJobsProvider), isEmpty);
    expect(await readStoredJobOfferIdentities(), isEmpty);
    expect(clearedAlerts, {jobId: offerId, legacyJobId: null});
    expect(ringtoneStopped, isTrue);
  });
}
