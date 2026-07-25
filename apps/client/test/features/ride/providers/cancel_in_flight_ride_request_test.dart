import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('preserves matching state when cancellation is authoritatively rejected',
      () async {
    final dio = _cancellationDio(readBackStatus: 'requested');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(RideService(dio))],
    );
    addTearDown(container.dispose);
    container.read(activeRideIdProvider.notifier).state = 'ride-1';

    final cancelled = await cancelInFlightRideRequest(container);

    expect(cancelled, isFalse);
    expect(container.read(activeRideIdProvider), 'ride-1');
    expect(
      container.read(bookingFailureMessageProvider),
      'Could not cancel the ride. Please try again.',
    );
  });

  test('clears matching state after timeout read-back proves cancellation',
      () async {
    final dio = _cancellationDio(readBackStatus: 'cancelled');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(RideService(dio))],
    );
    addTearDown(container.dispose);
    container.read(activeRideIdProvider.notifier).state = 'ride-1';

    final cancelled = await cancelInFlightRideRequest(container);

    expect(cancelled, isTrue);
    expect(container.read(activeRideIdProvider), isNull);
  });

  test(
      'waits for the authoritative ride id when cancellation wins the POST race',
      () async {
    final dio = _cancellationDio(readBackStatus: 'cancelled');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(RideService(dio))],
    );
    addTearDown(container.dispose);
    container.read(bookingPhaseProvider.notifier).startSearch();

    final cancellation = cancelInFlightRideRequest(container);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    container.read(activeRideIdProvider.notifier).state = 'ride-1';

    expect(await cancellation, isTrue);
    expect(container.read(activeRideIdProvider), isNull);
    expect(container.read(rideSearchCancellationRequestedProvider), isFalse);
  });
}

Dio _cancellationDio({required String readBackStatus}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.method == 'PATCH' &&
            options.path == '/rides/ride-1/cancel') {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
              message: 'ambiguous timeout',
            ),
          );
          return;
        }
        if (options.method == 'GET' && options.path == '/rides/ride-1') {
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{
                'success': true,
                'data': <String, dynamic>{
                  'id': 'ride-1',
                  'status': readBackStatus,
                },
              },
            ),
          );
          return;
        }
        handler.reject(
          DioException(
            requestOptions: options,
            message: 'Unexpected request ${options.method} ${options.path}',
          ),
        );
      },
    ),
  );
  return dio;
}
