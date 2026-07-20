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
      bookingKey: '018f47a2-7b3d-7cc3-8f5a-30a5f79a0f11',
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
    expect(
      capturedRequest.headers['Idempotency-Key'],
      '018f47a2-7b3d-7cc3-8f5a-30a5f79a0f11',
    );
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

  test('lookupBookingAttempt returns the live ride projection', () async {
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
                  'rideId': 'ride_123',
                  'status': 'requested',
                  'driversNotified': 1,
                  'initializationPending': false,
                },
              },
            ),
          );
        },
      ),
    );

    final result = await RideService(dio).lookupBookingAttempt(
      '018f47a2-7b3d-7cc3-8f5a-30a5f79a0f11',
    );

    expect(capturedRequest.method, 'GET');
    expect(
      capturedRequest.path,
      '/rides/booking-attempts/018f47a2-7b3d-7cc3-8f5a-30a5f79a0f11',
    );
    expect(result, {
      'rideId': 'ride_123',
      'status': 'requested',
      'driversNotified': 1,
      'initializationPending': false,
    });
  });

  test('lookupBookingAttempt maps only the definitive unused-key 404 to null',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 404,
                data: const {
                  'error': 'BOOKING_ATTEMPT_NOT_FOUND',
                  'message': 'No ride was created for this booking attempt.',
                },
              ),
            ),
          );
        },
      ),
    );

    expect(
      await RideService(dio).lookupBookingAttempt(
        '018f47a2-7b3d-7cc3-8f5a-30a5f79a0f11',
      ),
      isNull,
    );
  });

  test('lookupBookingAttempt does not hide an unrelated 404', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 404,
                data: const {
                  'error': 'ROUTE_NOT_FOUND',
                  'message': 'Route not found.',
                },
              ),
            ),
          );
        },
      ),
    );

    await expectLater(
      RideService(dio).lookupBookingAttempt(
        '018f47a2-7b3d-7cc3-8f5a-30a5f79a0f11',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.errorCode,
          'errorCode',
          'ROUTE_NOT_FOUND',
        ),
      ),
    );
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

    final result = await RideService(dio).acceptRideRequest(
      'ride_123',
      offerId: 'offer_456',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/rides/ride_123/accept');
    expect(capturedRequest.data, {'offerId': 'offer_456'});
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
      offerId: 'offer_456',
      reason: ' notification_skip ',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/rides/ride_123/decline');
    expect(capturedRequest.data, {
      'offerId': 'offer_456',
      'reason': 'notification_skip',
    });
  });

  test('acknowledgeRideOffer uses the idempotent receipt endpoint', () async {
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
                  'offerId': 'offer_456',
                  'decisionExpiresAt': '2026-07-17T12:00:45.000Z',
                },
              },
            ),
          );
        },
      ),
    );

    final result = await RideService(dio).acknowledgeRideOffer(
      'ride_123',
      'offer_456',
    );

    expect(capturedRequest.method, 'POST');
    expect(
      capturedRequest.path,
      '/rides/ride_123/offers/offer_456/received',
    );
    expect(result['offerId'], 'offer_456');
  });

  test('disputeRide sends the backend reason/details contract', () async {
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
                  'refundDestinationRequired': true,
                },
              },
            ),
          );
        },
      ),
    );

    final result = await RideService(dio).disputeRide(
      'ride_123',
      reason: 'Driver took an unnecessary detour',
      details: 'The route doubled back after the pickup.',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/rides/ride_123/dispute');
    expect(capturedRequest.data, {
      'reason': 'Driver took an unnecessary detour',
      'details': 'The route doubled back after the pickup.',
    });
    expect(result['refundDestinationRequired'], isTrue);
  });

  test('ride lifecycle transition sends the approved GPS proof contract',
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

    await RideService(dio).updateRideStatus(
      'ride_123',
      status: 'arrived_at_pickup',
      currentLat: 6.6885,
      currentLng: -1.6244,
      accuracyMeters: 12,
      capturedAt: DateTime.utc(2026, 7, 19, 3, 4, 5),
    );

    expect(capturedRequest.path, '/rides/ride_123/status');
    expect(capturedRequest.data, {
      'status': 'arrived_at_pickup',
      'currentLat': 6.6885,
      'currentLng': -1.6244,
      'accuracyMeters': 12.0,
      'capturedAt': '2026-07-19T03:04:05.000Z',
    });
  });

  test('ride lifecycle transition fails before HTTP when GPS proof is missing',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));

    await expectLater(
      RideService(dio).updateRideStatus(
        'ride_123',
        status: 'completed',
      ),
      throwsArgumentError,
    );
  });
}
