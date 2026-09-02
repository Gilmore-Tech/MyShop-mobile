import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/providers/socket_provider.dart';
import 'package:myshop_provider/src/features/driver_home/providers/ride_request_provider.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledRideService extends RideService {
  _ControlledRideService() : super(Dio());

  final acceptResult = Completer<Map<String, dynamic>>();
  final activeRideResult = Completer<Map<String, dynamic>?>();
  int acceptCalls = 0;
  int activeRideReads = 0;

  @override
  Future<Map<String, dynamic>> acceptRideRequest(
    String rideId, {
    required String offerId,
  }) {
    acceptCalls += 1;
    return acceptResult.future;
  }

  @override
  Future<Map<String, dynamic>?> getMyActiveRide() {
    activeRideReads += 1;
    return activeRideResult.future;
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
      createdAt: DateTime.utc(2026, 9, 2),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('duplicate overlay accepts share one operation and preserve socket ride',
      () async {
    final service = _ControlledRideService();
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.read(rideOfferIdByRideProvider.notifier).state = const {
      'ride-1': 'offer-1',
    };
    final notifier = container.read(activeRideProvider.notifier);

    final first = notifier.acceptRideFromNotification(
      'ride-1',
      offerId: 'offer-1',
    );
    final duplicate = notifier.acceptRideFromNotification(
      'ride-1',
      offerId: 'offer-1',
    );

    expect(service.acceptCalls, 1);
    notifier.applySnapshot(_ride('ride-1', RideStatus.driverEnRoute));
    service.acceptResult.complete(
      const {'rideId': 'ride-1', 'status': 'accepted'},
    );

    expect(await first, isTrue);
    expect(await duplicate, isTrue);
    expect(service.acceptCalls, 1);
    expect(service.activeRideReads, 0);
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.driverEnRoute,
    );
  });

  test('a transient null read cannot erase a socket-confirmed active ride',
      () async {
    final service = _ControlledRideService();
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.read(rideOfferIdByRideProvider.notifier).state = const {
      'ride-1': 'offer-1',
    };
    final notifier = container.read(activeRideProvider.notifier);

    final acceptance = notifier.acceptRideFromNotification(
      'ride-1',
      offerId: 'offer-1',
    );
    service.acceptResult.complete(
      const {'rideId': 'ride-1', 'status': 'accepted'},
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.activeRideReads, 1);

    notifier.applySnapshot(_ride('ride-1', RideStatus.driverEnRoute));
    service.activeRideResult.complete(null);

    expect(await acceptance, isTrue);
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.driverEnRoute,
    );
    expect(container.read(activeRideProvider).errorMessage, isNull);
  });

  test('a delayed old offer cannot clear a different active ride', () async {
    final service = _ControlledRideService();
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.driverEnRoute));

    final accepted = await notifier.acceptRideFromNotification(
      'ride-old',
      offerId: 'offer-old',
    );

    expect(accepted, isFalse);
    expect(service.acceptCalls, 0);
    expect(container.read(activeRideProvider).ride?.id, 'ride-current');
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.driverEnRoute,
    );
  });

  test('a delayed duplicate action reuses the already-active same ride',
      () async {
    final service = _ControlledRideService();
    final container = ProviderContainer(
      overrides: [rideServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    container.read(rideOfferIdByRideProvider.notifier).state = const {
      'ride-current': 'offer-current',
    };
    final notifier = container.read(activeRideProvider.notifier);
    notifier.restore(_ride('ride-current', RideStatus.driverEnRoute));

    final accepted = await notifier.acceptRideFromNotification(
      'ride-current',
      offerId: 'offer-current',
    );

    expect(accepted, isTrue);
    expect(service.acceptCalls, 0);
    expect(service.activeRideReads, 0);
    expect(container.read(activeRideProvider).ride?.id, 'ride-current');
    expect(
      container.read(activeRideProvider).ride?.status,
      RideStatus.driverEnRoute,
    );
  });
}
