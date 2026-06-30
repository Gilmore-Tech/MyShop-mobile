import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myshop_client/src/core/services/directions_service.dart';

void main() {
  test('uses the authenticated backend route contract without a Google key',
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
              data: {
                'success': true,
                'data': {
                  'polyline': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
                  'distanceMeters': 5400,
                  'durationSeconds': 732,
                },
              },
            ),
          );
        },
      ),
    );

    final route = await DirectionsService(dio).fetchRoute(
      origin: const LatLng(38.5, -120.2),
      destination: const LatLng(43.252, -126.453),
    );

    expect(capturedRequest.path, '/location/routes/compute');
    expect(capturedRequest.data, {
      'originLatitude': 38.5,
      'originLongitude': -120.2,
      'destinationLatitude': 43.252,
      'destinationLongitude': -126.453,
    });
    expect(capturedRequest.data, isNot(contains('key')));
    expect(route.isFallback, isFalse);
    expect(route.warningMessage, isNull);
    expect(route.polyline, hasLength(3));
    expect(route.distanceMeters, 5400);
    expect(route.durationSeconds, 732);
  });

  test('marks the direct-line fallback with an explicit warning', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'offline',
          ),
        ),
      ),
    );

    final route = await DirectionsService(dio).fetchRoute(
      origin: const LatLng(6.6885, -1.6244),
      destination: const LatLng(6.6978, -1.6803),
    );

    expect(route.isFallback, isTrue);
    expect(route.warningMessage, isNotEmpty);
    expect(route.polyline, hasLength(2));
  });
}
