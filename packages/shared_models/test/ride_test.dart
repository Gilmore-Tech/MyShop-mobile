import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  test('uses totalFare as the estimate for active rides', () {
    final ride = Ride.fromJson({
      'id': 'ride-1',
      'status': 'accepted',
      'totalFare': 3200,
      'pickupAddress': 'KNUST Gate',
      'dropoffAddress': 'Kejetia Market',
    });

    expect(ride.estimatedFarePesewas, 3200);
    expect(ride.finalFarePesewas, isNull);
    expect(ride.finalFareDisplay, 'GHS 32');
  });

  test('uses totalFare as final fare only for completed rides', () {
    final ride = Ride.fromJson({
      'id': 'ride-2',
      'status': 'completed',
      'totalFare': 4500,
      'estimatedFarePesewas': 3900,
      'pickupAddress': 'KNUST Gate',
      'dropoffAddress': 'Kejetia Market',
    });

    expect(ride.estimatedFarePesewas, 3900);
    expect(ride.finalFarePesewas, 4500);
    expect(ride.finalFareDisplay, 'GHS 45');
  });
}
