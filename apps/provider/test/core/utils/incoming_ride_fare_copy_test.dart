import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/utils/incoming_ride_fare_copy.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('promo offer shows the exact three price rows and ignores earnings', () {
    final copy = IncomingRideFareCopy.fromSnapshot(
      IncomingRideFareSnapshot.fromJson({
        'estimatedProviderEarningsPesewas': 800,
        'prePromoFarePesewas': 1000,
        'clientPayableEstimatePesewas': 600,
        'promoDiscountPesewas': 300,
        'loyaltyDiscountPesewas': 100,
        'platformDiscountPesewas': 400,
        'promoApplied': true,
        'estimatedFarePesewas': 600,
      }),
    );

    expect(copy.primaryLabel, 'EST. FULL FARE');
    expect(copy.primaryAmount, 'GHS 10.00');
    expect(copy.pricingLines.map((line) => '${line.label}: ${line.amount}'), [
      'EST. FULL FARE: GHS 10.00',
      'PROMO / DISCOUNT: - GHS 4.00',
      'CLIENT PRICE: GHS 6.00',
    ]);
    expect(
      copy.nativePricingSummary,
      'PROMO / DISCOUNT - GHS 4.00\nCLIENT PRICE GHS 6.00',
    );
  });

  test('fully subsidised offer preserves the zero client price', () {
    final copy = IncomingRideFareCopy.fromSnapshot(
      const IncomingRideFareSnapshot(
        prePromoFarePesewas: 1430,
        clientPayableEstimatePesewas: 0,
        platformDiscountPesewas: 1430,
        promoApplied: true,
        legacyEstimatedFarePesewas: 0,
      ),
    );

    expect(copy.primaryAmount, 'GHS 14.30');
    expect(copy.detailLines[0].label, 'PROMO / DISCOUNT');
    expect(copy.detailLines[0].amount, '- GHS 14.30');
    expect(copy.detailLines[1].label, 'CLIENT PRICE');
    expect(copy.detailLines[1].amount, 'GHS 0.00');
  });

  test('non-promo quote still renders all three explicit price rows', () {
    final copy = IncomingRideFareCopy.fromSnapshot(
      const IncomingRideFareSnapshot(
        prePromoFarePesewas: 1000,
        clientPayableEstimatePesewas: 1000,
        platformDiscountPesewas: 0,
        legacyEstimatedFarePesewas: 1000,
      ),
    );

    expect(copy.pricingLines.map((line) => '${line.label}: ${line.amount}'), [
      'EST. FULL FARE: GHS 10.00',
      'PROMO / DISCOUNT: - GHS 0.00',
      'CLIENT PRICE: GHS 10.00',
    ]);
  });

  test('legacy singleton is estimated fare and never settlement earnings', () {
    final ride = Ride(
      id: 'legacy-ride',
      clientId: 'client',
      status: RideStatus.requested,
      pickupAddress: 'Pickup',
      dropoffAddress: 'Dropoff',
      pickupLat: 0,
      pickupLng: 0,
      dropoffLat: 0,
      dropoffLng: 0,
      estimatedFarePesewas: 600,
      estimatedProviderEarningsPesewas: 800,
      providerEarningsPesewas: 999,
      estimatedDistanceKm: 1,
      estimatedDurationMins: 4,
      paymentMethod: 'cash',
      createdAt: DateTime.utc(2026),
    );
    final copy = IncomingRideFareCopy.fromSnapshot(
      IncomingRideFareSnapshot.fromRide(ride),
    );

    expect(copy.primaryKind, IncomingRidePrimaryAmountKind.legacyEstimatedFare);
    expect(copy.primaryLabel, 'ESTIMATED FARE');
    expect(copy.primaryAmount, 'GHS 6.00');
    expect(copy.detailLines, isEmpty);
  });

  test(
    'transitional quote reconciles prices despite a stale discount total',
    () {
      final fare = IncomingRideFareSnapshot.fromJson({
        'estimatedFarePesewas': 600,
        'estimatedProviderEarningsPesewas': 800,
        'prePromoFarePesewas': 1000,
        'platformDiscountPesewas': 999,
      });
      final copy = IncomingRideFareCopy.fromSnapshot(fare);

      expect(copy.primaryLabel, 'EST. FULL FARE');
      expect(fare.clientPayableEstimatePesewas, 600);
      expect(fare.totalDiscountPesewas, 400);
      expect(copy.detailLines[0].amount, '- GHS 4.00');
      expect(copy.detailLines[1].amount, 'GHS 6.00');
    },
  );

  test(
    'wire parser preserves zero and sums transitional discount components',
    () {
      final fare = IncomingRideFareSnapshot.fromJson({
        'estimatedProviderEarningsPesewas': '900',
        'clientPayableEstimatePesewas': '0',
        'promoDiscountPesewas': '700',
        'loyaltyDiscountPesewas': 300,
        'estimatedFarePesewas': '0',
      });

      expect(fare.clientPayableEstimatePesewas, 0);
      expect(fare.totalDiscountPesewas, 1000);
    },
  );

  test('client price above full fare does not render contradictory rows', () {
    final copy = IncomingRideFareCopy.fromSnapshot(
      const IncomingRideFareSnapshot(
        prePromoFarePesewas: 1000,
        clientPayableEstimatePesewas: 1200,
        platformDiscountPesewas: 0,
      ),
    );

    expect(copy.primaryLabel, 'EST. FULL FARE');
    expect(copy.detailLines, isEmpty);
  });

  test('malformed or negative push money fails soft to the legacy fare', () {
    final fare = IncomingRideFareSnapshot.fromJson({
      'estimatedProviderEarningsPesewas': -1,
      'prePromoFarePesewas': 'NaN',
      'clientPayableEstimatePesewas': 'Infinity',
      'platformDiscountPesewas': '-50',
      'estimatedFarePesewas': 500,
    });
    final copy = IncomingRideFareCopy.fromSnapshot(fare);

    expect(fare.prePromoFarePesewas, isNull);
    expect(fare.clientPayableEstimatePesewas, isNull);
    expect(fare.totalDiscountPesewas, isNull);
    expect(copy.primaryLabel, 'ESTIMATED FARE');
    expect(copy.primaryAmount, 'GHS 5.00');
  });
}
