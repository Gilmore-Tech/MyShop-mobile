import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/ride/data/ride_booking_attempt_store.dart';
import 'package:myshop_client/src/features/ride/providers/edit_trip_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingRideBookingAttemptStore extends RideBookingAttemptStore {
  int clearCalls = 0;

  @override
  Future<void> clear({String? bookingKey}) async {
    clearCalls++;
  }
}

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

  test('definitive pre-create no-driver failure resets locally without API',
      () async {
    final store = _RecordingRideBookingAttemptStore();
    final container = ProviderContainer(
      overrides: [
        rideBookingAttemptStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    container.read(bookingPhaseProvider.notifier).fail();
    container.read(bookingFailureExitModeProvider.notifier).state =
        BookingFailureExitMode.noRideCreated;
    container.read(bookingFailureMessageProvider.notifier).state = 'No drivers';
    container.read(driversNotifiedProvider.notifier).state = 3;
    container.read(rideMatchedViaSocketProvider.notifier).state = true;
    container.read(rideSearchProvider.notifier)
      ..setLocation(
        RideSearchField.pickup,
        const RideLocation(
          name: 'Office',
          address: 'Office',
          lat: 5.60,
          lng: -0.18,
        ),
      )
      ..setLocation(
        RideSearchField.destination,
        const RideLocation(
          name: 'Mall',
          address: 'Mall',
          lat: 5.61,
          lng: -0.17,
        ),
      );
    container.read(tripStopsProvider.notifier).seedPreTrip(
      pickup: (address: 'Office', lat: 5.60, lng: -0.18),
      destination: (address: 'Mall', lat: 5.61, lng: -0.17),
    );
    container.read(selectedVehicleProvider.notifier).state = 'comfort';

    expect(await dismissFailedRideRequest(container), isTrue);

    expect(store.clearCalls, 1);
    expect(container.read(bookingPhaseProvider), BookingPhase.idle);
    expect(container.read(bookingFailureMessageProvider), isNull);
    expect(
      container.read(bookingFailureExitModeProvider),
      BookingFailureExitMode.cancellationRequired,
    );
    expect(container.read(driversNotifiedProvider), 0);
    expect(container.read(rideMatchedViaSocketProvider), isFalse);
    expect(container.read(rideSearchProvider).pickup, isNull);
    expect(container.read(rideSearchProvider).destination, isNull);
    expect(container.read(tripStopsProvider), isEmpty);
    expect(container.read(selectedVehicleProvider), isEmpty);
  });

  test('an actual ride id always preserves authoritative cancellation',
      () async {
    final dio = _cancellationDio(readBackStatus: 'requested');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(RideService(dio))],
    );
    addTearDown(container.dispose);
    container.read(bookingPhaseProvider.notifier).fail();
    container.read(bookingFailureExitModeProvider.notifier).state =
        BookingFailureExitMode.noRideCreated;
    container.read(activeRideIdProvider.notifier).state = 'ride-1';

    expect(await dismissFailedRideRequest(container), isFalse);
    expect(container.read(activeRideIdProvider), 'ride-1');
    expect(container.read(bookingPhaseProvider), BookingPhase.failed);
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
