import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/ride/data/ride_booking_attempt_store.dart';
import 'package:myshop_client/src/features/ride/providers/edit_trip_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';

class _MockRideService extends Mock implements RideService {}

class _NoopRideBookingAttemptStore extends RideBookingAttemptStore {
  @override
  Future<void> clear({String? bookingKey}) async {}
}

void _seedRideRequestDraft(ProviderContainer container) {
  container.read(rideSearchProvider.notifier)
    ..setLocation(
      RideSearchField.pickup,
      const RideLocation(
        name: 'Office',
        address: 'Office pickup address',
        lat: 6.69,
        lng: -1.62,
      ),
    )
    ..setLocation(
      RideSearchField.destination,
      const RideLocation(
        name: 'Mall',
        address: 'Mall destination address',
        lat: 6.71,
        lng: -1.60,
      ),
    );
  container.read(tripStopsProvider.notifier).seedPreTrip(
    pickup: (address: 'Office pickup address', lat: 6.69, lng: -1.62),
    destination: (
      address: 'Mall destination address',
      lat: 6.71,
      lng: -1.60,
    ),
  );
  container.read(selectedVehicleProvider.notifier).state = 'comfort';
}

Map<String, dynamic> _completedSnapshot(String rideId) => {
      'id': rideId,
      'status': 'completed',
      'pickupAddress': 'Office pickup address',
      'dropoffAddress': 'Mall destination address',
      'totalFarePesewas': 2500,
      'paymentMethod': 'cash',
      'driver': {'name': 'Kofi Mensah'},
    };

void main() {
  test('explicit ride-flow exit clears every fare-estimate input', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    _seedRideRequestDraft(container);

    resetRideRequestDraft(container.read);

    expect(container.read(rideSearchProvider).pickup, isNull);
    expect(container.read(rideSearchProvider).destination, isNull);
    expect(container.read(tripStopsProvider), isEmpty);
    expect(container.read(selectedVehicleProvider), isEmpty);
  });

  test('completed snapshot preserves receipt before clearing the full draft',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _seedRideRequestDraft(container);
    container.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.inProgress;

    RideReceipt? receiptObservedAtCompletion;
    RideSearchState? searchObservedAtCompletion;
    List<TripStop>? stopsObservedAtCompletion;
    String? vehicleObservedAtCompletion;
    final subscription = container.listen<RideTrackingPhase>(
      rideTrackingPhaseProvider,
      (_, next) {
        if (next != RideTrackingPhase.completed) return;
        receiptObservedAtCompletion = container.read(rideReceiptProvider);
        searchObservedAtCompletion = container.read(rideSearchProvider);
        stopsObservedAtCompletion = container.read(tripStopsProvider);
        vehicleObservedAtCompletion = container.read(selectedVehicleProvider);
      },
    );
    addTearDown(subscription.close);

    applyCompletedRideSnapshot(
      container.read,
      _completedSnapshot('ride-socket'),
    );

    expect(receiptObservedAtCompletion?.rideId, 'ride-socket');
    expect(receiptObservedAtCompletion?.pickupAddress, 'Office pickup address');
    expect(searchObservedAtCompletion?.pickup, isNull);
    expect(searchObservedAtCompletion?.destination, isNull);
    expect(stopsObservedAtCompletion, isEmpty);
    expect(vehicleObservedAtCompletion, isEmpty);
  });

  test('REST completion recovery clears the full next-ride draft', () async {
    final rideService = _MockRideService();
    when(() => rideService.getRide('ride-rest')).thenAnswer(
      (_) async => _completedSnapshot('ride-rest'),
    );
    final container = ProviderContainer(
      overrides: [
        rideBookingAttemptStoreProvider.overrideWithValue(
          _NoopRideBookingAttemptStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    _seedRideRequestDraft(container);
    container.read(activeRideIdProvider.notifier).state = 'ride-rest';
    container.read(rideArrivalAnchorProvider.notifier).state = DateTime.utc(
      2026,
      8,
      22,
    );
    container.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.inProgress;

    await hydrateActiveRideFromRest(
      container.read,
      rideService,
      'ride-rest',
    );

    expect(container.read(rideReceiptProvider)?.rideId, 'ride-rest');
    expect(
      container.read(rideTrackingPhaseProvider),
      RideTrackingPhase.completed,
    );
    expect(container.read(rideArrivalAnchorProvider), isNull);
    expect(container.read(rideSearchProvider).pickup, isNull);
    expect(container.read(rideSearchProvider).destination, isNull);
    expect(container.read(tripStopsProvider), isEmpty);
    expect(container.read(selectedVehicleProvider), isEmpty);
  });

  test('late REST completion for an old ride cannot clear a new ride',
      () async {
    final rideService = _MockRideService();
    final oldRideResponse = Completer<Map<String, dynamic>>();
    when(() => rideService.getRide('ride-old'))
        .thenAnswer((_) => oldRideResponse.future);
    final container = ProviderContainer(
      overrides: [
        rideBookingAttemptStoreProvider.overrideWithValue(
          _NoopRideBookingAttemptStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(activeRideIdProvider.notifier).state = 'ride-old';

    final oldHydrate = hydrateActiveRideFromRest(
      container.read,
      rideService,
      'ride-old',
    );
    await pumpEventQueue();

    container.read(activeRideIdProvider.notifier).state = 'ride-new';
    _seedRideRequestDraft(container);
    container.read(rideSearchProvider.notifier).markSubmitted();
    container.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.enRoute;
    oldRideResponse.complete(_completedSnapshot('ride-old'));
    await oldHydrate;

    expect(container.read(activeRideIdProvider), 'ride-new');
    expect(container.read(rideSearchProvider).pickup?.name, 'Office');
    expect(container.read(rideSearchProvider).destination?.name, 'Mall');
    expect(container.read(rideSearchProvider).wasSubmitted, isTrue);
    expect(container.read(tripStopsProvider), hasLength(2));
    expect(container.read(selectedVehicleProvider), 'comfort');
    expect(
      container.read(rideTrackingPhaseProvider),
      RideTrackingPhase.enRoute,
    );
    expect(container.read(rideReceiptProvider), isNull);
  });

  test('replayed completion cannot wipe a newly-started draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    _seedRideRequestDraft(container);
    final snapshot = _completedSnapshot('ride-replayed');

    applyCompletedRideSnapshot(container.read, snapshot);
    _seedRideRequestDraft(container);
    container.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.enRoute;
    applyCompletedRideSnapshot(container.read, snapshot);

    expect(container.read(rideSearchProvider).pickup?.name, 'Office');
    expect(container.read(rideSearchProvider).destination?.name, 'Mall');
    expect(container.read(rideSearchProvider).wasSubmitted, isFalse);
    expect(container.read(tripStopsProvider), hasLength(2));
    expect(container.read(selectedVehicleProvider), 'comfort');
    expect(
      container.read(rideTrackingPhaseProvider),
      RideTrackingPhase.enRoute,
    );
  });
}
