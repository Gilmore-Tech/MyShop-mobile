import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  test('parses canonical and transitional positive ride tolls only', () {
    final canonical = Ride.fromJson({
      'id': 'ride-toll-canonical',
      'status': 'requested',
      'estimatedFarePesewas': 4500,
      'toll': {
        'label': 'Airport toll',
        'amountPesewas': 500,
        'applicationMode': 'dropoff',
      },
    });
    final transitional = Ride.fromJson({
      'id': 'ride-toll-flat',
      'status': 'requested',
      'estimatedFarePesewas': 4500,
      'tollFeePesewas': '500',
      'tollLabel': 'Airport toll',
    });

    expect(canonical.toll?.label, 'Airport toll');
    expect(canonical.tollFeePesewas, 500);
    expect(canonical.toll?.applicationMode, 'dropoff');
    expect(transitional.tollFeePesewas, 500);
  });

  test(
    'absent, zero, negative, and fractional tolls have no display model',
    () {
      for (final value in <Object?>[null, 0, -1, 1.5, '0', '1.5']) {
        final ride = Ride.fromJson({
          'id': 'ride-no-toll-$value',
          'status': 'requested',
          'estimatedFarePesewas': 4000,
          if (value != null)
            'toll': {'label': 'Airport toll', 'amountPesewas': value},
        });

        expect(ride.toll, isNull, reason: 'value=$value');
        expect(ride.tollFeePesewas, 0, reason: 'value=$value');
      }
    },
  );

  test('provider settlement conserves inclusive fare without mobile math', () {
    final ride = Ride.fromJson({
      'id': 'ride-toll-settlement',
      'status': 'completed',
      'prePromoFarePesewas': 4500,
      'finalFarePesewas': 4500,
      'toll': {'label': 'Airport toll', 'amountPesewas': 500},
      // 20% commission is charged on the 4000 transport fare only.
      'effectiveCommissionPesewas': 800,
      // Provider receives 3200 transport earnings + all 500 toll.
      'providerEarningsPesewas': 3700,
      'providerSettlementBasisPesewas': 4500,
      'financialsFinal': true,
    });

    expect(ride.tripFarePesewas, 4500);
    expect(ride.providerCommissionPesewas, 800);
    expect(ride.settledProviderEarningsPesewas, 3700);
    expect(ride.hasConservedProviderFinancials, isTrue);
  });

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

  test('distinguishes an omitted legacy estimate from a real zero quote', () {
    final omitted = Ride.fromJson({
      'id': 'ride-no-fare',
      'status': 'requested',
    });
    final zero = Ride.fromJson({
      'id': 'ride-zero-fare',
      'status': 'requested',
      'estimatedFarePesewas': 0,
    });

    expect(omitted.estimatedFarePesewas, 0);
    expect(omitted.hasEstimatedFareQuote, isFalse);
    expect(zero.hasEstimatedFareQuote, isTrue);
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

  test('legacy full fare wins over the client-paid amount', () {
    final ride = Ride.fromJson({
      'id': 'ride-legacy-two-fares',
      'status': 'completed',
      'estimatedFarePesewas': 9000,
      'finalFarePesewas': 10000,
      'totalPaidPesewas': 4000,
    });

    expect(ride.tripFarePesewas, 10000);
    expect(ride.tripFareDisplay, 'GHS 100');
    expect(ride.totalPaidPesewas, 4000);
  });

  test(
    'uses effective settlement commission and fails closed while pending',
    () {
      final finalRide = Ride.fromJson({
        'id': 'ride-relief-final',
        'status': 'completed',
        'prePromoFarePesewas': 10000,
        'commissionPesewas': 2000,
        'effectiveCommissionPesewas': 600,
        'providerSettlementBasisPesewas': 10000,
        'providerEarningsPesewas': 9400,
        'financialsFinal': true,
      });
      final pendingRide = Ride.fromJson({
        'id': 'ride-relief-pending',
        'status': 'completed',
        'commissionPesewas': 2000,
        'providerEarningsPesewas': 8000,
        'financialsFinal': false,
      });

      expect(finalRide.providerCommissionPesewas, 600);
      expect(finalRide.settledProviderEarningsPesewas, 9400);
      expect(pendingRide.providerCommissionPesewas, isNull);
      expect(pendingRide.settledProviderEarningsPesewas, isNull);
    },
  );

  test('malformed explicit final financial pairs fail closed together', () {
    for (final financials in <Map<String, dynamic>>[
      {'commissionPesewas': 2000, 'providerEarningsPesewas': 8000},
      {'effectiveCommissionPesewas': 2000},
      {'effectiveCommissionPesewas': 2000, 'providerEarningsPesewas': 8100},
      {
        'effectiveCommissionPesewas': 2000,
        'providerSettlementBasisPesewas': null,
        'providerEarningsPesewas': 8000,
      },
    ]) {
      final ride = Ride.fromJson({
        'id': 'ride-malformed-final',
        'status': 'completed',
        'prePromoFarePesewas': 10000,
        'providerSettlementBasisPesewas': 10000,
        'financialsFinal': true,
        ...financials,
      });

      expect(ride.providerCommissionPesewas, isNull);
      expect(ride.settledProviderEarningsPesewas, isNull);
    }
  });

  test('explicit final settlement money rejects strings and fractions', () {
    for (final field in <String>[
      'effectiveCommissionPesewas',
      'providerSettlementBasisPesewas',
      'providerEarningsPesewas',
    ]) {
      for (final malformed in <Object>['2000', 2000.5]) {
        final ride = Ride.fromJson({
          'id': 'ride-strict-final-money',
          'status': 'completed',
          'prePromoFarePesewas': 10000,
          'effectiveCommissionPesewas': 2000,
          'providerSettlementBasisPesewas': 10000,
          'providerEarningsPesewas': 8000,
          'financialsFinal': true,
          field: malformed,
        });

        expect(ride.hasConservedProviderFinancials, isFalse);
        expect(ride.providerCommissionPesewas, isNull);
        expect(ride.settledProviderEarningsPesewas, isNull);
        expect(ride.settledProviderSettlementBasisPesewas, isNull);
      }
    }
  });

  test('partial refund conserves against the retained settlement basis', () {
    final ride = Ride.fromJson({
      'id': 'ride-partial-refund',
      'status': 'completed',
      'prePromoFarePesewas': 10000,
      'effectiveCommissionPesewas': 1200,
      'providerSettlementBasisPesewas': 6000,
      'providerEarningsPesewas': 4800,
      'financialsFinal': true,
    });

    expect(ride.hasConservedProviderFinancials, isTrue);
    expect(ride.providerCommissionPesewas, 1200);
    expect(ride.settledProviderEarningsPesewas, 4800);
    expect(ride.settledProviderSettlementBasisPesewas, 6000);
  });

  test('full refund accepts a conserved zero settlement pair', () {
    final ride = Ride.fromJson({
      'id': 'ride-full-refund',
      'status': 'completed',
      'prePromoFarePesewas': 10000,
      'effectiveCommissionPesewas': 0,
      'providerSettlementBasisPesewas': 0,
      'providerEarningsPesewas': 0,
      'financialsFinal': true,
    });

    expect(ride.hasConservedProviderFinancials, isTrue);
    expect(ride.providerCommissionPesewas, 0);
    expect(ride.settledProviderEarningsPesewas, 0);
    expect(ride.settledProviderSettlementBasisPesewas, 0);
  });

  test('settlement basis above original fare fails closed', () {
    final ride = Ride.fromJson({
      'id': 'ride-invalid-refund-basis',
      'status': 'completed',
      'prePromoFarePesewas': 10000,
      'effectiveCommissionPesewas': 2000,
      'providerSettlementBasisPesewas': 11000,
      'providerEarningsPesewas': 9000,
      'financialsFinal': true,
    });

    expect(ride.hasConservedProviderFinancials, isFalse);
    expect(ride.providerCommissionPesewas, isNull);
    expect(ride.settledProviderEarningsPesewas, isNull);
    expect(ride.settledProviderSettlementBasisPesewas, isNull);
  });

  test('legacy policy commission and relieved earnings fail as one pair', () {
    final ride = Ride.fromJson({
      'id': 'ride-legacy-relief-mismatch',
      'status': 'completed',
      'prePromoFarePesewas': 10000,
      'commissionPesewas': 2000,
      'providerEarningsPesewas': 9400,
    });

    expect(ride.hasConservedProviderFinancials, isFalse);
    expect(ride.providerCommissionPesewas, isNull);
    expect(ride.settledProviderEarningsPesewas, isNull);
  });

  test(
    'present malformed financial finality never enables legacy fallback',
    () {
      for (final malformed in <Object?>['true', 1, null]) {
        final ride = Ride.fromJson({
          'id': 'ride-malformed-finality',
          'status': 'completed',
          'prePromoFarePesewas': 10000,
          'commissionPesewas': 2000,
          'providerEarningsPesewas': 8000,
          'financialsFinal': malformed,
        });

        expect(ride.hasFinancialsFinalContract, isTrue);
        expect(ride.providerCommissionPesewas, isNull);
        expect(ride.settledProviderEarningsPesewas, isNull);
        expect(ride.settledProviderSettlementBasisPesewas, isNull);
      }
    },
  );

  test('absent finality key retains conserved legacy compatibility', () {
    final ride = Ride.fromJson({
      'id': 'ride-legacy-conserved',
      'status': 'completed',
      'prePromoFarePesewas': 10000,
      'commissionPesewas': 2000,
      'providerEarningsPesewas': 8000,
    });

    expect(ride.hasFinancialsFinalContract, isFalse);
    expect(ride.providerCommissionPesewas, 2000);
    expect(ride.settledProviderEarningsPesewas, 8000);
    expect(ride.settledProviderSettlementBasisPesewas, 10000);
  });

  test(
    'parses the additive incoming-offer fare contract including zero quote',
    () {
      final ride = Ride.fromJson({
        'id': 'ride-offer-fare',
        'status': 'requested',
        // Legacy post-discount rider quote remains separate.
        'estimatedFarePesewas': 0,
        'estimatedProviderEarningsPesewas': '1144',
        'prePromoFarePesewas': 1430,
        'clientPayableEstimatePesewas': 0,
        'promoDiscountPesewas': 1000,
        'loyaltyDiscountPesewas': 430,
        'platformDiscountPesewas': 1430,
        'providerEarningsPesewas': 999,
        'pickupAddress': 'KNUST Gate',
        'dropoffAddress': 'Kejetia Market',
      });

      expect(ride.estimatedProviderEarningsPesewas, 1144);
      expect(ride.prePromoFarePesewas, 1430);
      expect(ride.clientPayableEstimatePesewas, 0);
      expect(ride.promoDiscountPesewas, 1000);
      expect(ride.loyaltyDiscountPesewas, 430);
      expect(ride.platformDiscountPesewas, 1430);
      // Settlement earnings remain a separate field.
      expect(ride.providerEarningsPesewas, 999);
    },
  );

  test(
    'keeps legacy payment rate unknown instead of fabricating 20 percent',
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
    },
  );
}
