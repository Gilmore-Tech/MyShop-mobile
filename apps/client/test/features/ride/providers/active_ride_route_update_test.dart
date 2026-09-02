import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/edit_trip_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('applies only a newer complete route projection for the active ride',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeRideIdProvider.notifier).state = 'ride-123';
    container.read(matchedDriverProvider.notifier).state = const MatchedDriver(
      name: 'Ama',
      vehicle: 'Toyota Vitz',
      plateNumber: 'GT 1234-26',
      rating: 4.9,
      minutesAway: 2,
      driversAvailable: 1,
      promoDiscountPesewas: 500,
      toll: RideToll(label: 'Old toll', amountPesewas: 200),
    );

    final revisionTwo = RideRouteUpdate.fromJson({
      'rideId': 'ride-123',
      'routeRevision': 2,
      'destination': {
        'address': 'KNUST',
        'lat': 6.6732,
        'lng': -1.5654,
      },
      'estimatedFarePesewas': 4600,
      'projectedDistanceMeters': 8000,
      'projectedDurationSeconds': 1200,
    });
    final staleRevision = RideRouteUpdate.fromJson({
      'rideId': 'ride-123',
      'routeRevision': 1,
      'destination': {
        'address': 'Adum',
        'lat': 6.6885,
        'lng': -1.6244,
      },
    });

    expect(
      applyActiveRideRouteUpdate(container.read, revisionTwo),
      isTrue,
    );
    expect(
      applyActiveRideRouteUpdate(container.read, staleRevision),
      isFalse,
    );
    expect(
      container.read(activeRideRouteUpdateProvider)?.routeRevision,
      2,
    );
    expect(
      container.read(rideSearchProvider).destination?.address,
      'KNUST',
    );
    final matched = container.read(matchedDriverProvider);
    expect(matched?.confirmedFarePesewas, 4600);
    expect(matched?.distanceKm, 8);
    expect(matched?.promoDiscountPesewas, 0);
    expect(matched?.toll, isNull);
    expect(
      container.read(fareRecalculationProvider).originalFarePesewas,
      4600,
    );
  });

  test('does not advance the revision for a thin route event', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeRideIdProvider.notifier).state = 'ride-123';

    final thin = RideRouteUpdate.fromJson({
      'rideId': 'ride-123',
      'routeRevision': 3,
    });

    expect(applyActiveRideRouteUpdate(container.read, thin), isFalse);
    expect(container.read(activeRideRouteUpdateProvider), isNull);
  });
}
