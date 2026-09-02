import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('declineJobRequest clears only the artisan invitation', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {'acknowledged': true},
              },
            ),
          );
        },
      ),
    );

    await JobService(dio).declineJobRequest(
      'job_123',
      reason: ' overlay_skip ',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/jobs/job_123/decline');
    expect(capturedRequest.data, {'reason': 'overlay_skip'});
  });

  test('declineJobRequest includes the exact offer identity when present',
      () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'success': true,
                'data': {'acknowledged': true},
              },
            ),
          );
        },
      ),
    );

    await JobService(dio).declineJobRequest(
      'job_123',
      offerId: ' offer_456 ',
      reason: 'provider_declined',
    );

    expect(capturedRequest.path, '/jobs/job_123/decline');
    expect(capturedRequest.data, {
      'offerId': 'offer_456',
      'reason': 'provider_declined',
    });
  });

  test('acknowledgeJobOffer uses the exact authenticated receipt endpoint',
      () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'success': true,
                'data': {
                  'jobId': 'job_123',
                  'offerId': 'offer_456',
                  'state': 'active',
                },
              },
            ),
          );
        },
      ),
    );

    final result =
        await JobService(dio).acknowledgeJobOffer('job_123', 'offer_456');

    expect(capturedRequest.method, 'POST');
    expect(
      capturedRequest.path,
      '/jobs/job_123/offers/offer_456/received',
    );
    expect(capturedRequest.data, isNull);
    expect(result['offerId'], 'offer_456');
  });

  test('disputeJob sends the backend reason/details contract', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 201,
              data: {
                'success': true,
                'data': {
                  'disputeId': 'dispute_123',
                  'status': 'open',
                  'refundDestinationRequired': false,
                },
              },
            ),
          );
        },
      ),
    );

    await JobService(dio).disputeJob(
      'job_123',
      reason: 'Work quality was poor or incomplete',
      details: 'Only one of three requested sockets was installed.',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/jobs/job_123/dispute');
    expect(capturedRequest.data, {
      'reason': 'Work quality was poor or incomplete',
      'details': 'Only one of three requested sockets was installed.',
    });
  });

  test('artisan lifecycle transition sends the approved GPS proof contract',
      () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'success': true,
                'data': <String, dynamic>{},
              },
            ),
          );
        },
      ),
    );

    await JobService(dio).updateJobStatus(
      'job_123',
      status: 'in_progress',
      currentLat: 6.6885,
      currentLng: -1.6244,
      accuracyMeters: 9,
      capturedAt: DateTime.utc(2026, 7, 19, 3, 4, 5),
    );

    expect(capturedRequest.path, '/jobs/job_123/status');
    expect(capturedRequest.data, {
      'status': 'in_progress',
      'currentLat': 6.6885,
      'currentLng': -1.6244,
      'accuracyMeters': 9.0,
      'capturedAt': '2026-07-19T03:04:05.000Z',
    });
  });

  test(
      'artisan lifecycle transition fails before HTTP when GPS proof is missing',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));

    await expectLater(
      JobService(dio).updateJobStatus(
        'job_123',
        status: 'artisan_marked_complete',
      ),
      throwsArgumentError,
    );
  });
}
