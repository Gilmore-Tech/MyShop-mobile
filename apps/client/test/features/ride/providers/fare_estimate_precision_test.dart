import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/ride/providers/fare_estimate_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';

void main() {
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
}
