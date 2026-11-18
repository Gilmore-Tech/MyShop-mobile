import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> payload() => {
        'id': 'job-1',
        'status': 'open',
        'categoryId': 'category-1',
        'clientName': 'Ama Mensah',
      };

  test('keeps the booking region while hydrating and copying a job', () {
    final job = Job.fromJson({...payload(), 'regionId': 'bono'});
    expect(job.regionId, 'bono');
    expect(job.copyWith(description: 'Updated description').regionId, 'bono');
  });

  test('accepts snake-case regions and older jobs without a region', () {
    expect(
      Job.fromJson({...payload(), 'region_id': 'ashanti'}).regionId,
      'ashanti',
    );
    expect(Job.fromJson(payload()).regionId, isNull);
  });
}
