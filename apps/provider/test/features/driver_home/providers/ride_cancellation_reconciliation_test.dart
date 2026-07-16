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

  @override
  Future<Map<String, dynamic>> getRide(String rideId) async => rideResponse;
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

void main() {
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
      ..rideResponse = {
        'id': 'ride-current',
        'clientId': 'client-1',
        'driverId': 'driver-1',
        'status': 'cancelled',
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
