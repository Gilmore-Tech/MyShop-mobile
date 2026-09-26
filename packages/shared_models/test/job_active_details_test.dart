import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  test('parses the active client contact and accepted bid duration', () {
    final job = Job.fromJson({
      'id': 'job-1',
      'status': 'confirmed',
      'categoryId': 'category-1',
      'description': 'Repair a door',
      'client': {
        'name': 'Client One',
        'user': {'phoneNormalized': '+233241234567'},
      },
      'acceptedBid': {
        'durationMinutes': 2 * 24 * 60,
      },
    });

    expect(job.clientPhone, '+233241234567');
    expect(job.agreedDurationMinutes, 2880);
  });

  test('copyWith preserves and can update agreed duration', () {
    final job = Job.fromJson({
      'id': 'job-1',
      'status': 'confirmed',
      'categoryId': 'category-1',
      'description': 'Repair a door',
      'acceptedBid': {'durationMinutes': 120},
    });

    expect(job.copyWith().agreedDurationMinutes, 120);
    expect(job.copyWith(agreedDurationMinutes: 180).agreedDurationMinutes, 180);
  });
}
