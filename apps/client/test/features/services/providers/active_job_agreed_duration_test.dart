import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/services/providers/active_job_provider.dart';

class _FakeJobService extends JobService {
  _FakeJobService() : super(Dio());

  @override
  Future<Map<String, dynamic>> getJob(String jobId) async => {
        'id': jobId,
        'status': 'artisan_en_route',
        'description': 'Repair a door',
        'addressText': 'Kumasi',
        'category': {'name': 'Carpentry'},
        'artisan': {
          'id': 'artisan-1',
          'name': 'Kofi Mensah',
        },
        'acceptedBid': {
          'amountPesewas': 15000,
          'etaMinutes': 12,
          'durationMinutes': 3 * 24 * 60,
        },
      };
}

void main() {
  test('active job exposes accepted duration in days', () async {
    final container = ProviderContainer(
      overrides: [
        jobServiceProvider.overrideWithValue(_FakeJobService()),
      ],
    );
    addTearDown(container.dispose);

    final job = await container.read(activeJobProvider('job-1').future);

    expect(job.completionLabel, '3 days');
    expect(job.etaLabel, '12 mins away');
  });
}
