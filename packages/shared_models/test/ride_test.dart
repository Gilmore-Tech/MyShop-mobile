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

  test('reads distance and duration from meter/second payloads', () {
    final ride = Ride.fromJson({
      'id': 'ride-3',
      'status': 'requested',
      'estimatedFarePesewas': 2500,
      'pickupAddress': 'KNUST Gate',
      'dropoffAddress': 'Kejetia Market',
      'distanceMeters': 5400,
      'durationSeconds': 732,
    });

    expect(ride.estimatedDistanceKm, 5.4);
    expect(ride.estimatedDurationMins, 12);
    expect(ride.distanceDisplay, '5.4 km');
    expect(ride.durationDisplay, '12 mins');
  });

  test('parses the immutable payment commission snapshot', () {
    final ride = Ride.fromJson({
      'id': 'ride-4',
      'status': 'completed',
      'estimatedFarePesewas': 10000,
      'totalPaidPesewas': 8500,
      'commissionPesewas': 1456,
      'commissionRatePercent': '17.13',
      'netPayoutPesewas': 7044,
      'pickupAddress': 'KNUST Gate',
      'dropoffAddress': 'Kejetia Market',
    });

    expect(ride.commissionPesewas, 1456);
    expect(ride.commissionRatePercent, 17.13);
    expect(ride.netPayoutPesewas, 7044);
  });

  test(
      'fully-subsidised promo ride keeps the metered fare as the driver pay '
      'base (regression: 0.00 everywhere)', () {
    // Mirrors the staging trip: fare 1430p, campaign covered all of it.
    final ride = Ride.fromJson({
      'id': 'ride-promo',
      'status': 'completed',
      'estimatedFarePesewas': 2600,
      'finalFarePesewas': 0,
      'totalPaidPesewas': 0,
      'prePromoFarePesewas': 1430,
      'promoDiscountPesewas': 1430,
      'promoApplied': true,
      'collectFromClientPesewas': 0,
      'commissionPesewas': 286,
      'commissionRatePercent': '20.00',
      'netPayoutPesewas': 1144,
      'providerEarningsPesewas': 1144,
      'pickupAddress': 'KNUST Gate',
      'dropoffAddress': 'Kejetia Market',
    });

    // The trip fare is the pre-promo metered fare — totalPaid of 0 must not
    // swallow it.
    expect(ride.tripFarePesewas, 1430);
    expect(ride.tripFareDisplay, 'GHS 14.30');
    expect(ride.promoApplied, isTrue);
    expect(ride.promoDiscountPesewas, 1430);
    expect(ride.collectFromClientPesewas, 0);
    expect(ride.providerEarningsPesewas, 1144);
    // Client-paid figure remains truthfully 0.
    expect(ride.totalPaidPesewas, 0);
  });

  test('infers promoApplied from a non-zero discount on legacy payloads', () {
    final ride = Ride.fromJson({
      'id': 'ride-legacy-promo',
      'status': 'completed',
      'estimatedFarePesewas': 2000,
      'prePromoFarePesewas': 2000,
      'promoDiscountPesewas': 500,
      'pickupAddress': 'KNUST Gate',
      'dropoffAddress': 'Kejetia Market',
    });

    expect(ride.promoApplied, isTrue);
  });

  test('keeps legacy payment rate unknown instead of fabricating 20 percent',
      () {
    const summary = TripSummary(
      rideId: 'ride-legacy',
      clientName: 'Passenger',
      clientRating: 5,
      paymentMethod: 'Cash',
      pickupAddress: 'KNUST Gate',
      dropoffAddress: 'Kejetia Market',
      distanceKm: 1,
      durationMins: 5,
      baseFarePesewas: 0,
      distanceFarePesewas: 0,
      timeFarePesewas: 0,
      totalFarePesewas: 1000,
      commissionPesewas: 200,
      payoutMethod: 'MoMo',
      payoutStatus: 'PROCESSING',
    );

    expect(summary.commissionLabel, 'Platform Commission');
    expect(summary.commissionDisplay, 'GHS 2');
  });
}
