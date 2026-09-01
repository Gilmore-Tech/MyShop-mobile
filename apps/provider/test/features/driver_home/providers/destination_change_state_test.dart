import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/driver_home/providers/ride_request_provider.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('provider applies newer destination and ignores a stale revision', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.applySnapshot(_ride(revision: 1, destination: 'Adum'));

    expect(
      notifier.applyDestinationChanged(
        _ride(revision: 2, destination: 'KNUST'),
      ),
      isTrue,
    );
    expect(container.read(activeRideProvider).ride?.dropoffAddress, 'KNUST');
    expect(
      container.read(driverDestinationChangeNoticeProvider)?.routeRevision,
      2,
    );

    expect(
      notifier.applyDestinationChanged(
        _ride(revision: 1, destination: 'Old destination'),
      ),
      isFalse,
    );
    expect(container.read(activeRideProvider).ride?.dropoffAddress, 'KNUST');
  });

  test('older lifecycle snapshot cannot roll back the destination', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeRideProvider.notifier);
    notifier.applySnapshot(
      _ride(
        revision: 3,
        destination: 'KNUST',
        promoDiscountPesewas: 300,
        toll: const RideToll(label: 'New toll', amountPesewas: 200),
      ),
    );

    notifier.applySnapshot(
      _ride(
        revision: 2,
        destination: 'Adum',
        status: RideStatus.arrived,
      ),
    );

    final ride = container.read(activeRideProvider).ride;
    expect(ride?.status, RideStatus.arrived);
    expect(ride?.routeRevision, 3);
    expect(ride?.dropoffAddress, 'KNUST');
    expect(ride?.promoDiscountPesewas, 300);
    expect(ride?.toll?.amountPesewas, 200);
  });
}

Ride _ride({
  required int revision,
  required String destination,
  RideStatus status = RideStatus.inProgress,
  int? promoDiscountPesewas,
  RideToll? toll,
}) {
  return Ride(
    id: 'ride-123',
    clientId: 'client-123',
    driverId: 'driver-123',
    status: status,
    pickupAddress: 'Airport',
    dropoffAddress: destination,
    pickupLat: 6.70,
    pickupLng: -1.60,
    dropoffLat: revision == 1 ? 6.68 : 6.67,
    dropoffLng: revision == 1 ? -1.62 : -1.56,
    estimatedFarePesewas: 4600,
    promoDiscountPesewas: promoDiscountPesewas,
    promoApplied: (promoDiscountPesewas ?? 0) > 0,
    toll: toll,
    estimatedDistanceKm: 8,
    estimatedDurationMins: 20,
    paymentMethod: 'cash',
    createdAt: DateTime.utc(2026, 9, 1),
    routeRevision: revision,
  );
}
