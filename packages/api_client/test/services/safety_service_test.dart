import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions capturedRequest;
  late SafetyService service;

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
                'data': {'status': 'activated'},
              },
            ),
          );
        },
      ),
    );
    service = SafetyService(dio);
  });

  test('sends a global SOS without invented booking or GPS context', () async {
    await service.triggerEmergency();

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/emergency');
    expect(capturedRequest.data, isEmpty);
  });

  test('includes complete active-booking and device-location context',
      () async {
    await service.triggerEmergency(
      bookingType: 'job',
      bookingId: '00000000-0000-4000-8000-000000000001',
      latitude: 6.6885,
      longitude: -1.6244,
    );

    expect(capturedRequest.data, {
      'bookingType': 'job',
      'bookingId': '00000000-0000-4000-8000-000000000001',
      'latitude': 6.6885,
      'longitude': -1.6244,
    });
  });

  test('rejects partial optional context before making a request', () async {
    expect(
      () => service.triggerEmergency(bookingType: 'ride'),
      throwsArgumentError,
    );
    expect(
      () => service.triggerEmergency(latitude: 6.6885),
      throwsArgumentError,
    );
  });
}
