import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';

void main() {
  test('keeps inclusive total authoritative and adds toll once in fallback',
      () {
    final authoritative = RideFareFields.fromSnapshot({
      'finalFarePesewas': 4500,
      'baseFarePesewas': 1000,
      'distanceFarePesewas': 3000,
      'toll': {'label': 'Airport toll', 'amountPesewas': 500},
    });
    final componentFallback = RideFareFields.fromSnapshot({
      'baseFarePesewas': 1000,
      'distanceFarePesewas': 3000,
      'tollFeePesewas': 500,
      'tollLabel': 'Airport toll',
    });

    expect(authoritative.totalFarePesewas, 4500);
    expect(authoritative.toll?.amountPesewas, 500);
    expect(componentFallback.totalFarePesewas, 4500);
    expect(componentFallback.subtotalPesewas, 4000);
  });

  test('zero toll produces no receipt charge model', () {
    final receipt = buildRideReceiptFromSnapshot({
      'id': 'ride-no-toll',
      'finalFarePesewas': 4000,
      'toll': {'label': 'Airport toll', 'amountPesewas': 0},
    });

    expect(receipt.toll, isNull);
    expect(receipt.totalPaidPesewas, 4000);
  });

  test('completed receipt carries a positive toll inside the inclusive total',
      () {
    final receipt = buildRideReceiptFromSnapshot({
      'id': 'ride-with-toll',
      'finalFarePesewas': 4500,
      'baseFarePesewas': 1000,
      'distanceFarePesewas': 3000,
      'toll': {'label': 'Airport toll', 'amountPesewas': 500},
    });

    expect(receipt.toll?.label, 'Airport toll');
    expect(receipt.toll?.amountPesewas, 500);
    expect(receipt.totalPaidPesewas, 4500);
    expect(receipt.subtotalPesewas, 4000);
  });

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

  test(
      'fully-subsidised promo ride keeps the pre-promo subtotal and a '
      'truthful zero total (regression: 0.00 everywhere)', () {
    final receipt = buildRideReceiptFromSnapshot({
      'id': 'ride-promo',
      'finalFarePesewas': 0,
      'grossFarePesewas': 0,
      'totalPaidPesewas': 0,
      'prePromoFarePesewas': 1430,
      'promoDiscountPesewas': 1430,
      'promoApplied': true,
      'baseFarePesewas': 500,
      'distanceFarePesewas': 930,
      'estimatedFarePesewas': 2600,
      'paymentMethod': 'cash',
      'driver': {'name': 'Kofi Driver'},
    });

    // Subtotal is the metered fare BEFORE the discount — grossFarePesewas
    // (the post-promo charge, 0 here) must not win.
    expect(receipt.subtotalPesewas, 1430);
    expect(receipt.promoDiscountPesewas, 1430);
    expect(receipt.baseFarePesewas, 500);
    expect(receipt.distanceFarePesewas, 930);
    // The rider genuinely paid nothing.
    expect(receipt.totalPaidPesewas, 0);
  });

  test('builds receipts with total paid winning over gross final fare', () {
    final receipt = buildRideReceiptFromSnapshot({
      'id': 'ride-2',
      'finalFarePesewas': 5100,
      'grossFarePesewas': 5100,
      'totalPaidPesewas': 4300,
      'loyaltyDiscountPesewas': 800,
      'estimatedFarePesewas': 4400,
      'baseFare': 800,
      'distanceFarePesewas': 3300,
      'paymentMethod': 'cash',
      'driver': {
        'name': 'Kofi Driver',
      },
    });

    expect(receipt.totalPaidPesewas, 4300);
    expect(receipt.loyaltyDiscountPesewas, 800);
    expect(receipt.subtotalPesewas, 5100);
    expect(receipt.driverName, 'Kofi Driver');
  });
}
