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
}
