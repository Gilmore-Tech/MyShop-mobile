import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions capturedRequest;
  late NotificationService service;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
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
                'data': {'registered': true},
              },
            ),
          );
        },
      ),
    );
    service = NotificationService(dio);
  });

  test('registers the ActivityKit push-to-start token', () async {
    await service.registerLiveActivityDevice(
      pushToStartToken: 'push-to-start-token',
    );

    expect(capturedRequest.method, 'POST');
    expect(
      capturedRequest.path,
      '/notifications/register-live-activity-device',
    );
    expect(capturedRequest.data, {
      'platform': 'ios',
      'pushToStartToken': 'push-to-start-token',
    });
  });

  test('registers a per-offer ActivityKit update token', () async {
    await service.registerLiveActivity(
      activityId: 'activity-1',
      updateToken: 'update-token',
      offerId: '37cfe2f2-a5d2-4515-a1f5-330545ed2d5c',
      requestType: 'ride',
      requestId: '60d4cfb6-c198-453a-af51-c787624951a9',
      expiresAt: DateTime.parse('2026-07-15T12:00:45+00:00'),
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/notifications/register-live-activity');
    expect(capturedRequest.data, {
      'platform': 'ios',
      'activityId': 'activity-1',
      'updateToken': 'update-token',
      'offerId': '37cfe2f2-a5d2-4515-a1f5-330545ed2d5c',
      'requestType': 'ride',
      'requestId': '60d4cfb6-c198-453a-af51-c787624951a9',
      'expiresAt': '2026-07-15T12:00:45.000Z',
    });
  });

  test('unregisters ActivityKit tokens with stale-token guards', () async {
    await service.unregisterLiveActivityDevice(
      pushToStartToken: 'push-to-start-token',
    );

    expect(capturedRequest.method, 'DELETE');
    expect(
      capturedRequest.path,
      '/notifications/register-live-activity-device',
    );
    expect(capturedRequest.data, {
      'platform': 'ios',
      'pushToStartToken': 'push-to-start-token',
    });

    await service.unregisterLiveActivity(
      activityId: 'activity-1',
      updateToken: 'update-token',
    );

    expect(capturedRequest.method, 'DELETE');
    expect(capturedRequest.path, '/notifications/register-live-activity');
    expect(capturedRequest.data, {
      'platform': 'ios',
      'activityId': 'activity-1',
      'updateToken': 'update-token',
    });
  });
}
