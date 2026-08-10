import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/utils/incoming_ride_fare_copy.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  test('promo cash offer shows earnings, both quotes, and MyShop cover', () {
    final copy = IncomingRideFareCopy.fromSnapshot(
      const IncomingRideFareSnapshot(
        estimatedProviderEarningsPesewas: 800,
        prePromoFarePesewas: 1000,
        clientPayableEstimatePesewas: 600,
        promoDiscountPesewas: 300,
        loyaltyDiscountPesewas: 100,
        platformDiscountPesewas: 400,
        promoApplied: true,
        legacyEstimatedFarePesewas: 600,
      ),
      paymentMethod: 'cash',
    );

    expect(copy.primaryLabel, 'ESTIMATED EARNINGS');
    expect(copy.primaryAmount, 'GHS 8.00');
    expect(copy.detailLines.map((line) => '${line.label}: ${line.amount}'), [
      'EST. FULL FARE: GHS 10.00',
      'RIDER QUOTE · CASH: GHS 6.00',
      'MYSHOP COVERS: GHS 4.00',
    ]);
  });

  test('fully subsidised in-app offer preserves the zero rider quote', () {
    final copy = IncomingRideFareCopy.fromSnapshot(
      const IncomingRideFareSnapshot(
        estimatedProviderEarningsPesewas: 1144,
        prePromoFarePesewas: 1430,
        clientPayableEstimatePesewas: 0,
        platformDiscountPesewas: 1430,
        promoApplied: true,
        legacyEstimatedFarePesewas: 0,
      ),
      paymentMethod: 'momo_mtn',
    );

    expect(copy.detailLines[1].label, 'RIDER QUOTE · IN APP');
    expect(copy.detailLines[1].amount, 'GHS 0.00');
    expect(copy.detailLines[2].amount, 'GHS 14.30');
  });

  test('non-promo quote combines identical trip and rider values', () {
    final copy = IncomingRideFareCopy.fromSnapshot(
      const IncomingRideFareSnapshot(
        estimatedProviderEarningsPesewas: 800,
        prePromoFarePesewas: 1000,
        clientPayableEstimatePesewas: 1000,
        platformDiscountPesewas: 0,
        legacyEstimatedFarePesewas: 1000,
      ),
      paymentMethod: 'cash',
    );

    expect(copy.detailLines, hasLength(1));
    expect(
      copy.detailLines.single.label,
      'EST. FULL FARE · RIDER QUOTE · CASH',
    );
    expect(copy.detailLines.single.amount, 'GHS 10.00');
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
      providerEarningsPesewas: 999,
      estimatedDistanceKm: 1,
      estimatedDurationMins: 4,
      paymentMethod: 'cash',
      createdAt: DateTime.utc(2026),
    );
    final copy = IncomingRideFareCopy.fromSnapshot(
      IncomingRideFareSnapshot.fromRide(ride),
      paymentMethod: ride.paymentMethod,
    );

    expect(copy.primaryKind, IncomingRidePrimaryAmountKind.legacyEstimatedFare);
    expect(copy.primaryLabel, 'ESTIMATED FARE');
    expect(copy.primaryAmount, 'GHS 6.00');
    expect(copy.detailLines, isEmpty);
  });

  test('transitional additive payload may use legacy quote as rider quote', () {
    final fare = IncomingRideFareSnapshot.fromJson({
      'estimatedFarePesewas': 600,
      'estimatedProviderEarningsPesewas': 800,
      'prePromoFarePesewas': 1000,
      'platformDiscountPesewas': 400,
    });
    final copy = IncomingRideFareCopy.fromSnapshot(
      fare,
      paymentMethod: 'cash',
    );

    expect(copy.primaryLabel, 'ESTIMATED EARNINGS');
    expect(fare.clientPayableEstimatePesewas, 600);
    expect(copy.detailLines[1].label, 'RIDER QUOTE · CASH');
  });

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
      expect(fare.myShopCoveredPesewas, 1000);
    },
  );

  test('malformed or negative push money fails soft to the legacy fare', () {
    final fare = IncomingRideFareSnapshot.fromJson({
      'estimatedProviderEarningsPesewas': -1,
      'prePromoFarePesewas': 'NaN',
      'clientPayableEstimatePesewas': 'Infinity',
      'platformDiscountPesewas': '-50',
      'estimatedFarePesewas': 500,
    });
    final copy = IncomingRideFareCopy.fromSnapshot(fare);

    expect(fare.estimatedProviderEarningsPesewas, isNull);
    expect(fare.prePromoFarePesewas, isNull);
    expect(fare.clientPayableEstimatePesewas, isNull);
    expect(fare.myShopCoveredPesewas, isNull);
    expect(copy.primaryLabel, 'ESTIMATED FARE');
    expect(copy.primaryAmount, 'GHS 5.00');
  });
}
