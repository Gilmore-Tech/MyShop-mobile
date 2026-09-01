import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/artisan_home/widgets/incoming_job_modal.dart';
import 'package:myshop_provider/src/core/providers/socket_provider.dart';
import 'package:myshop_provider/src/core/services/job_offer_receipt_service.dart';
import 'package:myshop_provider/src/features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetJobOfferReceiptMemoryForTesting();
  });

  testWidgets('modal expiry removes the job from the pending inbox',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final job = Job(
      id: '11111111-1111-4111-8111-111111111111',
      status: JobStatus.open,
      categoryId: 'plumbing',
      description: 'Repair a tap',
      latitude: 5.6,
      longitude: -0.2,
      expiresAt: DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String(),
    );
    container.read(pendingIncomingJobsProvider.notifier).enqueue(job);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: IncomingJobModal(job: job)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(pendingIncomingJobsProvider), isEmpty);
  });

  testWidgets('offer A timer cannot expire sequential offer B', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final firstDeadline = DateTime.now().toUtc().add(
          const Duration(milliseconds: 200),
        );
    final job = Job(
      id: '11111111-1111-4111-8111-111111111111',
      status: JobStatus.open,
      categoryId: 'plumbing',
      description: 'Repair a tap',
      latitude: 5.6,
      longitude: -0.2,
      expiresAt: firstDeadline.toIso8601String(),
    );
    container.read(jobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-a',
    };
    container.read(lastJobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-a',
    };
    container.read(jobOfferDeadlineByJobProvider.notifier).state = {
      job.id: firstDeadline,
    };
    container.read(pendingIncomingJobsProvider.notifier).enqueue(job);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: IncomingJobModal(job: job)),
        ),
      ),
    );
    await tester.pump();

    final secondDeadline =
        DateTime.now().toUtc().add(const Duration(seconds: 5));
    container.read(jobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-b',
    };
    container.read(lastJobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-b',
    };
    container.read(jobOfferDeadlineByJobProvider.notifier).state = {
      job.id: secondDeadline,
    };
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(jobOfferIdByJobProvider)[job.id], 'offer-b');
    expect(
      container.read(pendingIncomingJobsProvider).map((item) => item.id),
      contains(job.id),
    );
  });

  testWidgets('replacement offer owns a reused absolute deadline',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deadline =
        DateTime.now().toUtc().add(const Duration(milliseconds: 200));
    final job = Job(
      id: '11111111-1111-4111-8111-111111111111',
      status: JobStatus.open,
      categoryId: 'plumbing',
      description: 'Repair a tap',
      latitude: 5.6,
      longitude: -0.2,
      expiresAt: deadline.toIso8601String(),
    );
    container.read(jobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-a',
    };
    container.read(lastJobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-a',
    };
    container.read(jobOfferDeadlineByJobProvider.notifier).state = {
      job.id: deadline,
    };
    container.read(pendingIncomingJobsProvider.notifier).enqueue(job);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: IncomingJobModal(job: job)),
        ),
      ),
    );
    await tester.pump();

    container.read(jobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-b',
    };
    container.read(lastJobOfferIdByJobProvider.notifier).state = {
      job.id: 'offer-b',
    };
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(jobOfferIdByJobProvider), isNot(contains(job.id)));
    expect(container.read(pendingIncomingJobsProvider), isEmpty);
  });
}
