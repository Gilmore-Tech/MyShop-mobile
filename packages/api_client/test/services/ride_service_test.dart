import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('estimate sends ordered stops using backend lat/lng contract', () async {
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
                  'distanceKm': 7.2,
                  'durationMins': 18,
                  'surgeMultiplier': 1,
                  'categories': const [],
                },
              },
            ),
          );
        },
      ),
    );

    await RideService(dio).estimate(
      pickupLat: 6.6885,
      pickupLng: -1.6244,
      destinationLat: 6.7094,
      destinationLng: -1.5917,
      stops: const [
        {'lat': 6.7012, 'lng': -1.6168},
      ],
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/rides/estimate');
    expect(capturedRequest.data, {
      'pickupLat': 6.6885,
      'pickupLng': -1.6244,
      'dropoffLat': 6.7094,
      'dropoffLng': -1.5917,
      'stops': [
        {'lat': 6.7012, 'lng': -1.6168},
      ],
    });
  });

  test('createRide sends booking-time stops with addressText', () async {
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
                'data': {'rideId': 'ride_123', 'status': 'requested'},
              },
            ),
          );
        },
      ),
    );

    await RideService(dio).createRide(
      pickupLat: 6.6885,
      pickupLng: -1.6244,
      destinationLat: 6.7094,
      destinationLng: -1.5917,
      paymentMethod: 'cash',
      stops: const [
        {'lat': 6.7012, 'lng': -1.6168, 'addressText': 'KNUST Junction'},
      ],
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/rides');
    expect(capturedRequest.data, {
      'pickupLat': 6.6885,
      'pickupLng': -1.6244,
      'dropoffLat': 6.7094,
      'dropoffLng': -1.5917,
      'stops': [
        {'lat': 6.7012, 'lng': -1.6168, 'addressText': 'KNUST Junction'},
      ],
      'paymentMethod': 'cash',
    });
  });

  test('addStop uses backend latitude/longitude/addressText contract',
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
                  'stopId': 'stop_123',
                  'newFarePesewas': 4200,
                  'outsidePilotRegion': false,
                },
              },
            ),
          );
        },
      ),
    );

    final result = await RideService(dio).addStop(
      'ride_123',
      lat: 6.695,
      lng: -1.612,
      address: 'Kejetia Market, Kumasi',
    );

    expect(capturedRequest.method, 'PATCH');
    expect(capturedRequest.path, '/rides/ride_123/stops');
    expect(capturedRequest.data, {
      'latitude': 6.695,
      'longitude': -1.612,
      'addressText': 'Kejetia Market, Kumasi',
    });
    expect(result['stopId'], 'stop_123');
    expect(result['newFarePesewas'], 4200);
  });

  test('acceptRideRequest uses the notification-action REST endpoint',
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
                'data': {'rideId': 'ride_123', 'status': 'accepted'},
              },
            ),
          );
        },
      ),
    );

    final result = await RideService(dio).acceptRideRequest('ride_123');

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/rides/ride_123/accept');
    expect(result, {'rideId': 'ride_123', 'status': 'accepted'});
  });

  test('declineRideRequest sends an optional reason', () async {
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

    await RideService(dio).declineRideRequest(
      'ride_123',
      reason: ' notification_skip ',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/rides/ride_123/decline');
    expect(capturedRequest.data, {'reason': 'notification_skip'});
  });
}
