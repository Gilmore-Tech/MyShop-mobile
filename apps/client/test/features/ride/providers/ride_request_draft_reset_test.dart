import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/edit_trip_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';

void main() {
  test('explicit ride-flow exit clears every fare-estimate input', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(rideSearchProvider.notifier)
      ..setLocation(
        RideSearchField.pickup,
        const RideLocation(
          name: 'Pickup',
          address: 'Pickup address',
          lat: 6.69,
          lng: -1.62,
        ),
      )
      ..setLocation(
        RideSearchField.destination,
        const RideLocation(
          name: 'Destination',
          address: 'Destination address',
          lat: 6.71,
          lng: -1.60,
        ),
      );
    container.read(tripStopsProvider.notifier).seedPreTrip(
      pickup: (address: 'Pickup address', lat: 6.69, lng: -1.62),
      destination: (
        address: 'Destination address',
        lat: 6.71,
        lng: -1.60,
      ),
    );
    container.read(selectedVehicleProvider.notifier).state = 'comfort';

    resetRideRequestDraft(container.read);

    expect(container.read(rideSearchProvider).pickup, isNull);
    expect(container.read(rideSearchProvider).destination, isNull);
    expect(container.read(tripStopsProvider), isEmpty);
    expect(container.read(selectedVehicleProvider), isEmpty);
  });
}
