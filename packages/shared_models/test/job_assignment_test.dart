import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  test('parses the additive directed-assignment envelope', () {
    final job = Job.fromJson({
      'id': 'job-1',
      'status': 'admin_assigned',
      'categoryId': 'category-1',
      'description': 'Repair socket',
      'latitude': 5.6,
      'longitude': -0.2,
      'assignment': {
        'attemptId': 'attempt-1',
        'revision': 3,
        'phase': 'awaiting_client_accept',
        'quoteDeadlineAt': '2026-08-30T12:00:00.000Z',
        'acceptDeadlineAt': '2026-08-30T12:30:00.000Z',
      },
    });

    expect(job.isAdminAssigned, isTrue);
    expect(job.assignment?.attemptId, 'attempt-1');
    expect(job.assignment?.revision, 3);
    expect(job.assignment?.phase, JobAssignmentPhase.awaitingClientAccept);
    expect(job.assignment?.quoteDeadline?.isUtc, isTrue);
  });

  test('legacy jobs remain valid without an assignment envelope', () {
    final job = Job.fromJson({
      'id': 'job-2',
      'status': 'open',
      'categoryId': 'category-1',
      'description': 'Repair tap',
      'latitude': 5.6,
      'longitude': -0.2,
    });

    expect(job.assignment, isNull);
    expect(job.isAdminAssigned, isFalse);
  });

  test('unknown future assignment phases do not break job parsing', () {
    final job = Job.fromJson({
      'id': 'job-3',
      'status': 'admin_assigned',
      'categoryId': 'category-1',
      'description': 'Repair gate',
      'latitude': 5.6,
      'longitude': -0.2,
      'assignment': {'phase': 'future_phase'},
    });

    expect(job.assignment, isNotNull);
    expect(job.assignment?.phase, isNull);
  });
}
