import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/artisan_home/screens/bid_submission_screen.dart';
import 'package:myshop_provider/src/features/artisan_home/screens/job_request_screen.dart';
import 'package:myshop_provider/src/features/artisan_home/widgets/bid_status_banner.dart';
import 'package:shared_models/shared_models.dart';

Job _directedJob(JobAssignmentPhase phase) => Job(
      id: 'job-1',
      status: JobStatus.adminAssigned,
      categoryId: 'category-1',
      description: 'Repair socket',
      latitude: 5.6,
      longitude: -0.2,
      assignedArtisanId: 'artisan-1',
      assignment: JobAssignment(phase: phase),
    );

void main() {
  test('directed job can be quoted only during awaiting_quote by its artisan',
      () {
    expect(
      isJobBiddableForArtisan(
        _directedJob(JobAssignmentPhase.awaitingQuote),
        artisanUserId: 'artisan-1',
      ),
      isTrue,
    );
    expect(
      isJobBiddableForArtisan(
        _directedJob(JobAssignmentPhase.awaitingQuote),
        artisanUserId: 'artisan-2',
      ),
      isFalse,
    );
    expect(
      isJobBiddableForArtisan(
        _directedJob(JobAssignmentPhase.awaitingClientAccept),
        artisanUserId: 'artisan-1',
      ),
      isFalse,
    );
  });

  test('admin assignment alone never routes a submitted quote to active work',
      () {
    expect(submittedBidResponseIsConfirmed({'status': 'submitted'}), isFalse);
    expect(
      submittedBidResponseIsConfirmed({
        'status': 'submitted',
        'jobStatus': 'admin_assigned',
      }),
      isFalse,
    );
    expect(submittedBidResponseIsConfirmed({'status': 'accepted'}), isTrue);
    expect(
      submittedBidResponseIsConfirmed({
        'job': {'status': 'confirmed'},
      }),
      isTrue,
    );
  });

  test('directed request actions say quote and decline assignment', () {
    final labels = jobRequestActionLabels(directedAssignment: true);
    expect(labels.primary, 'Submit quote');
    expect(labels.secondary, 'Decline assignment');
  });

  testWidgets('submitted directed quote clearly waits for the client',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BidStatusBanner(
            status: BidStatus.pending,
            showCountdown: false,
            directedAssignment: true,
          ),
        ),
      ),
    );

    expect(find.text('Waiting for client'), findsOneWidget);
    expect(
      find.textContaining('do not start work before confirmation'),
      findsOneWidget,
    );
    expect(find.text('Quote when ready'), findsNothing);
  });
}
