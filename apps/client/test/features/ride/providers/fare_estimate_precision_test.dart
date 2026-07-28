import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/ride/providers/edit_trip_provider.dart';
import 'package:myshop_client/src/features/ride/providers/fare_estimate_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';

void main() {
  test('address-only locations are never precise booking points', () {
    const addressOnly = RideLocation(
      name: 'Home',
      address: 'Suame, Kumasi',
    );
    const coordinateBacked = RideLocation(
      name: 'Kejetia',
      address: 'Kejetia Market',
      lat: 6.6930,
      lng: -1.6100,
    );

    expect(addressOnly.hasCoordinates, isFalse);
    expect(addressOnly.isPrecise, isFalse);
    expect(coordinateBacked.hasCoordinates, isTrue);
    expect(coordinateBacked.isPrecise, isTrue);
  });

  test('booking coordinates must be finite and inside geographic bounds', () {
    final invalidLocations = <RideLocation>[
      const RideLocation(
        name: 'NaN latitude',
        address: 'Invalid',
        lat: double.nan,
        lng: 0,
      ),
      const RideLocation(
        name: 'Infinite longitude',
        address: 'Invalid',
        lat: 0,
        lng: double.infinity,
      ),
      const RideLocation(
        name: 'Latitude above range',
        address: 'Invalid',
        lat: 90.0001,
        lng: 0,
      ),
      const RideLocation(
        name: 'Latitude below range',
        address: 'Invalid',
        lat: -90.0001,
        lng: 0,
      ),
      const RideLocation(
        name: 'Longitude above range',
        address: 'Invalid',
        lat: 0,
        lng: 180.0001,
      ),
      const RideLocation(
        name: 'Longitude below range',
        address: 'Invalid',
        lat: 0,
        lng: -180.0001,
      ),
    ];

    for (final location in invalidLocations) {
      expect(location.hasCoordinates, isFalse, reason: location.name);
      expect(location.isPrecise, isFalse, reason: location.name);
    }

    for (final location in const <RideLocation>[
      RideLocation(
        name: 'North east boundary',
        address: 'Boundary',
        lat: 90,
        lng: 180,
      ),
      RideLocation(
        name: 'South west boundary',
        address: 'Boundary',
        lat: -90,
        lng: -180,
      ),
    ]) {
      expect(location.hasCoordinates, isTrue, reason: location.name);
      expect(location.isPrecise, isTrue, reason: location.name);
    }
  });

  test('does not request a fare for a broad area centroid', () async {
    var requestCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestCount++;
          handler.reject(
            DioException(
              requestOptions: options,
              message: 'Area centroids must not reach the estimate API',
            ),
          );
        },
      ),
    );
    final container = ProviderContainer(
      overrides: [
        rideServiceProvider.overrideWithValue(RideService(dio)),
      ],
    );
    addTearDown(container.dispose);

    final search = container.read(rideSearchProvider.notifier);
    search.setLocation(
      RideSearchField.pickup,
      const RideLocation(
        name: 'Current location',
        address: 'Accra, Ghana',
        lat: 5.6037,
        lng: -0.1870,
      ),
    );
    search.setLocation(
      RideSearchField.destination,
      const RideLocation(
        name: 'Tema',
        address: 'Tema, Ghana',
        lat: 5.6698,
        lng: -0.0166,
        precision: RideLocationPrecision.area,
      ),
    );

    final options = await container.read(fareEstimateProvider.future);

    expect(options, isEmpty);
    expect(requestCount, 0);
  });

  test('reads estimate distance from meters when kilometres are absent',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'distanceMeters': 5400,
                  'durationSeconds': 732,
                  'surgeMultiplier': 1.0,
                  'categories': [
                    {
                      'slug': 'regular',
                      'name': 'Regular',
                      'estimatedFarePesewas': 2500,
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final container = ProviderContainer(
      overrides: [
        rideServiceProvider.overrideWithValue(RideService(dio)),
      ],
    );
    addTearDown(container.dispose);

    final search = container.read(rideSearchProvider.notifier);
    search.setLocation(
      RideSearchField.pickup,
      const RideLocation(
        name: 'Current location',
        address: 'Accra, Ghana',
        lat: 5.6037,
        lng: -0.1870,
      ),
    );
    search.setLocation(
      RideSearchField.destination,
      const RideLocation(
        name: 'Kejetia',
        address: 'Kejetia Market',
        lat: 6.6930,
        lng: -1.6100,
      ),
    );

    final options = await container.read(fareEstimateProvider.future);

    expect(options, hasLength(1));
    expect(options.single.distanceKm, 5.4);
    expect(options.single.durationMins, 12);
  });

  test('sends ordered stops to estimate when pre-trip multistop is enabled',
      () async {
    late RequestOptions estimateRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/config/ride_multistop_pretrip_enabled') {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'key': 'ride_multistop_pretrip_enabled',
                    'value': 'true',
                  },
                },
              ),
            );
            return;
          }

          estimateRequest = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'distanceKm': 8.1,
                  'durationMins': 21,
                  'surgeMultiplier': 1.0,
                  'categories': [
                    {
                      'slug': 'regular',
                      'name': 'Regular',
                      'estimatedFarePesewas': 3200,
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final container = ProviderContainer(
      overrides: [
        rideServiceProvider.overrideWithValue(RideService(dio)),
        platformConfigServiceProvider.overrideWithValue(
          PlatformConfigService(dio),
        ),
      ],
    );
    addTearDown(container.dispose);

    final search = container.read(rideSearchProvider.notifier);
    search.setLocation(
      RideSearchField.pickup,
      const RideLocation(
        name: 'Current location',
        address: 'Adum',
        lat: 6.6885,
        lng: -1.6244,
      ),
    );
    search.setLocation(
      RideSearchField.destination,
      const RideLocation(
        name: 'Bantama',
        address: 'Bantama',
        lat: 6.7094,
        lng: -1.5917,
      ),
    );
    container.read(tripStopsProvider.notifier).seedPreTrip(
      pickup: (address: 'Adum', lat: 6.6885, lng: -1.6244),
      destination: (address: 'Bantama', lat: 6.7094, lng: -1.5917),
    );
    container.read(tripStopsProvider.notifier).addIntermediateStop(
          'KNUST Junction',
          lat: 6.7012,
          lng: -1.6168,
        );

    final options = await container.read(fareEstimateProvider.future);

    expect(options, hasLength(1));
    expect(estimateRequest.path, '/rides/estimate');
    expect(estimateRequest.data['stops'], [
      {'lat': 6.7012, 'lng': -1.6168},
    ]);
  });
}
