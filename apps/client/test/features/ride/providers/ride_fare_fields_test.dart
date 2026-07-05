import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';

void main() {
  test('reads modern and legacy fare aliases from snapshots', () {
    final fare = RideFareFields.fromSnapshot({
      'finalFarePesewas': 4200,
      'estimatedFarePesewas': 3600,
      'baseFarePesewas': 500,
      'distanceFare': 2100,
      'bookingFeePesewas': 300,
      'actualDistanceKm': 8.4,
      'actualDurationMins': 24,
      'surgeMultiplier': 1.25,
    });

    expect(fare.totalFarePesewas, 4200);
    expect(fare.baseFarePesewas, 500);
    expect(fare.distanceFarePesewas, 2100);
    expect(fare.bookingFeePesewas, 300);
    expect(fare.distanceKm, 8.4);
    expect(fare.durationMins, 24);
    expect(fare.surgeMultiplier, 1.25);
  });

  test('falls back to the estimated fare when final fare is not present', () {
    final fare = RideFareFields.fromSnapshot({
      'estimatedFarePesewas': 2750,
      'distanceKm': 5.2,
      'durationMins': 17,
    });

    expect(fare.totalFarePesewas, 2750);
    expect(fare.distanceKm, 5.2);
    expect(fare.durationMins, 17);
  });

  test('reads distance and duration from meters and seconds snapshots', () {
    final fare = RideFareFields.fromSnapshot({
      'estimatedFarePesewas': 2750,
      'distanceMeters': 5400,
      'durationSeconds': 732,
    });

    expect(fare.distanceKm, 5.4);
    expect(fare.durationMins, 12);
  });

  test('builds receipts with final fare winning over estimate', () {
    final receipt = buildRideReceiptFromSnapshot({
      'id': 'ride-1',
      'finalFarePesewas': 5100,
      'estimatedFarePesewas': 4400,
      'baseFare': 800,
      'distanceFarePesewas': 3300,
      'taxesPesewas': 100,
      'dropoffAddress': 'Kejetia Market',
      'paymentMethod': 'momo_mtn',
      'driver': {
        'firstName': 'Ama',
        'lastName': 'Boateng',
        'vehicle': 'Toyota Vitz',
      },
    });

    expect(receipt.totalPaidPesewas, 5100);
    expect(receipt.baseFarePesewas, 800);
    expect(receipt.distanceFarePesewas, 3300);
    expect(receipt.taxesPesewas, 100);
    expect(receipt.driverName, 'Ama Boateng');
  });
}
