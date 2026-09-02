import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/providers/socket_provider.dart';
import 'package:myshop_provider/src/features/driver_home/providers/ride_request_provider.dart';

class _FakeRideService extends RideService {
  _FakeRideService() : super(Dio());

  late Map<String, dynamic> rideResponse;
  Object? cancelError;
  Object? declineError;
  int declineCalls = 0;
  Map<String, dynamic> cancelResponse = const <String, dynamic>{};
  Map<String, dynamic> statusResponse = const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> getRide(String rideId) async => rideResponse;

  @override
  Future<Map<String, dynamic>> cancelRide(
    String rideId, {
    String? reason,
  }) async {
    final error = cancelError;
    if (error != null) throw error;
    return cancelResponse;
  }

  @override
  Future<void> declineRideRequest(
    String rideId, {
    required String offerId,
    String? reason,
  }) async {
    declineCalls += 1;
    final error = declineError;
    if (error != null) throw error;
  }

  @override
  Future<Map<String, dynamic>> updateRideStatus(
    String rideId, {
    required String status,
    double? currentLat,
    double? currentLng,
    double? accuracyMeters,
    DateTime? capturedAt,
  }) async {
    return statusResponse;
  }
}

Ride _ride(String id, RideStatus status) => Ride(
      id: id,
      clientId: 'client-1',
      driverId: 'driver-1',
      status: status,
      pickupAddress: 'Pickup',
      dropoffAddress: 'Destination',
      pickupLat: 6.6885,
      pickupLng: -1.6244,
      dropoffLat: 6.7094,
      dropoffLng: -1.5917,
      estimatedFarePesewas: 1500,
      estimatedDistanceKm: 4.2,
      estimatedDurationMins: 12,
      paymentMethod: 'cash',
      createdAt: DateTime.utc(2026, 7, 15),
    );

Map<String, dynamic> _rideJson(String id, String status) => {
      'id': id,
      'clientId': 'client-1',
      'driverId': 'driver-1',
      'status': status,
      'pickupAddress': 'Pickup',
      'dropoffAddress': 'Destination',
      'pickupLat': 6.6885,
      'pickupLng': -1.6244,
      'dropoffLat': 6.7094,
      'dropoffLng': -1.5917,
      'estimatedFarePesewas': 1500,
      'estimatedDistanceKm': 4.2,
      'estimatedDurationMins': 12,
      'paymentMethod': 'cash',
      'createdAt': '2026-07-15T12:00:00.000Z',
    };

void main() {
  test('notification decline requires an exact offer identity', () async {
    final service = _FakeRideService();
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final declined = await container
        .read(activeRideProvider.notifier)
        .declineRideFromNotification('ride-current');

    expect(declined, isFalse);
    expect(service.declineCalls, 0);
  });

  test('failed REST decline keeps the exact offer actionable locally',
      () async {
    final service = _FakeRideService()
      ..declineError = const NetworkException(message: 'offline');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.read(rideOfferIdByRideProvider.notifier).state = const {
      'ride-current': 'offer-current',
    };

    final declined = await container
        .read(activeRideProvider.notifier)
        .declineRideFromNotification('ride-current');

    expect(declined, isFalse);
    expect(service.declineCalls, 1);
    expect(
      container.read(rideOfferIdByRideProvider)['ride-current'],
      'offer-current',
    );
  });

  test('acknowledged REST decline consumes the exact offer identity', () async {
    final service = _FakeRideService();
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.read(rideOfferIdByRideProvider.notifier).state = const {
      'ride-current': 'offer-current',
    };

    final declined = await container
        .read(activeRideProvider.notifier)
        .declineRideFromNotification('ride-current');

    expect(declined, isTrue);
    expect(service.declineCalls, 1);
    expect(
      container.read(rideOfferIdByRideProvider).containsKey('ride-current'),
      isFalse,
    );
  });

  test('remote cancellation only terminates the matching active ride', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.driverEnRoute));

    expect(notifier.applyRemoteCancellation('ride-old'), isFalse);
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.driverEnRoute,
    );

    expect(notifier.applyRemoteCancellation('ride-current'), isTrue);
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.cancelled,
    );
  });

  test('socket reconnect reconciles a background-cancelled ride', () async {
    final service = _FakeRideService()
      ..rideResponse = _rideJson('ride-current', 'cancelled');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.driverEnRoute));

    await notifier.reconcileTrackedRide();

    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.cancelled,
    );
  });

  test('driver timeout read-back clears only a confirmed cancelled ride',
      () async {
    final service = _FakeRideService()
      ..cancelError = const NetworkException(message: 'timeout')
      ..rideResponse = _rideJson('ride-current', 'cancelled');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.driverEnRoute));

    final outcome = await notifier.cancelRide(reason: 'driver_cancelled');

    expect(outcome.cancelled, isTrue);
    expect(container.read(activeRideProvider).ride, isNull);
  });

  test('driver cancellation rejection preserves an authoritative active ride',
      () async {
    final service = _FakeRideService()
      ..cancelError = const ApiException(
        message: 'raw backend detail',
        statusCode: 400,
        errorCode: 'RIDE_NOT_CANCELLABLE',
      )
      ..rideResponse = _rideJson('ride-current', 'driver_en_route');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.driverEnRoute));

    final outcome = await notifier.cancelRide(reason: 'driver_cancelled');

    expect(outcome.cancelled, isFalse);
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.driverEnRoute,
    );
    expect(
      container.read(activeRideProvider).errorMessage,
      'This ride can no longer be cancelled.',
    );
  });

  test('malformed lifecycle acknowledgement does not invent a driver status',
      () async {
    final service = _FakeRideService()
      ..statusResponse = const <String, dynamic>{}
      ..rideResponse = _rideJson('ride-current', 'accepted');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.accepted));

    final updated = await notifier.markEnRoute();

    expect(updated, isFalse);
    expect(
        container.read(activeRideProvider).ride?.status, RideStatus.accepted);
    expect(
      container.read(activeRideProvider).errorMessage,
      contains("couldn't confirm"),
    );
  });

  test('read-back may confirm a committed driver lifecycle transition',
      () async {
    final service = _FakeRideService()
      ..statusResponse = const <String, dynamic>{}
      ..rideResponse = _rideJson('ride-current', 'driver_en_route');
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.accepted));

    final updated = await notifier.markEnRoute();

    expect(updated, isTrue);
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.driverEnRoute,
    );
  });

  test('cancellation event parser rejects unrelated status updates', () {
    expect(
      rideCancellationIdFromEvent({'rideId': 'ride-1'}),
      'ride-1',
    );
    expect(
      rideCancellationIdFromEvent(
        {'rideId': 'ride-1', 'status': 'cancelled'},
        requireCancelledStatus: true,
      ),
      'ride-1',
    );
    expect(
      rideCancellationIdFromEvent(
        {'rideId': 'ride-1', 'status': 'in_progress'},
        requireCancelledStatus: true,
      ),
      isNull,
    );
  });
}
