import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/services/providers/job_form_provider.dart';

class _MockJobService extends Mock implements JobService {}

class _MockMediaService extends Mock implements MediaService {}

void main() {
  late _MockJobService jobService;
  late JobFormNotifier notifier;

  setUp(() {
    jobService = _MockJobService();
    notifier = JobFormNotifier(jobService, _MockMediaService())
      ..selectCategory('plumbing', 'Plumbing')
      ..setTitle('Leaking pipe')
      ..setDescription('Please repair the kitchen pipe')
      ..setLocation(
        address: 'Family home, Sunyani',
        latitude: 7.3349,
        longitude: -2.3268,
      );
  });

  test('submits the selected job location without requiring device location',
      () async {
    when(
      () => jobService.createJob(
        categoryId: 'plumbing',
        description: 'Leaking pipe\n\nPlease repair the kitchen pipe',
        latitude: 7.3349,
        longitude: -2.3268,
        addressText: 'Family home, Sunyani',
        scheduledFor: null,
        photoUrls: null,
      ),
    ).thenAnswer((_) async => <String, dynamic>{'jobId': 'job-1'});

    expect(await notifier.submit(), 'job-1');

    verify(
      () => jobService.createJob(
        categoryId: 'plumbing',
        description: 'Leaking pipe\n\nPlease repair the kitchen pipe',
        latitude: 7.3349,
        longitude: -2.3268,
        addressText: 'Family home, Sunyani',
        scheduledFor: null,
        photoUrls: null,
      ),
    ).called(1);
  });

  test('maps an outside selected job location to clear final-step copy',
      () async {
    when(
      () => jobService.createJob(
        categoryId: 'plumbing',
        description: 'Leaking pipe\n\nPlease repair the kitchen pipe',
        latitude: 7.3349,
        longitude: -2.3268,
        addressText: 'Family home, Sunyani',
        scheduledFor: null,
        photoUrls: null,
      ),
    ).thenThrow(
      const ApiException(
        message: 'Internal geofence rejection text',
        statusCode: 400,
        errorCode: 'OUTSIDE_SERVICE_AREA',
      ),
    );

    expect(await notifier.submit(), isNull);
    expect(notifier.state.errorMessage, outsideJobServiceAreaMessage);
    expect(notifier.state.errorMessage, isNot(contains('geofence')));
  });
}
