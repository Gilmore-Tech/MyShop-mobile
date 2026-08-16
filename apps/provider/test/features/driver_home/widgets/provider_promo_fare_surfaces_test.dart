import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/driver_home/providers/ride_request_provider.dart';
import 'package:myshop_provider/src/features/driver_home/screens/active_ride_screen.dart';
import 'package:myshop_provider/src/features/driver_home/screens/driver_ride_complete_screen.dart';
import 'package:myshop_provider/src/features/driver_home/widgets/recent_activity_section.dart';
import 'package:myshop_provider/src/features/trips/providers/driver_trips_provider.dart';
import 'package:shared_models/shared_models.dart';

class _SeededActiveRideNotifier extends ActiveRideNotifier {
  _SeededActiveRideNotifier(super.ref, Ride ride) {
    state = ActiveRideState(ride: ride);
  }
}

Ride _promoRide({
  String id = 'promo-ride-12345678',
  bool financialsFinal = true,
  int settlementBasisPesewas = 1430,
  int effectiveCommissionPesewas = 186,
  int providerEarningsPesewas = 1244,
}) =>
    Ride(
      id: id,
      clientId: 'client-1',
      status: RideStatus.completed,
      pickupAddress: 'KNUST Gate',
      dropoffAddress: 'Kejetia Market',
      pickupLat: 0,
      pickupLng: 0,
      dropoffLat: 0,
      dropoffLng: 0,
      estimatedFarePesewas: 0,
      finalFarePesewas: 430,
      totalPaidPesewas: 0,
      prePromoFarePesewas: 1430,
      promoDiscountPesewas: 1000,
      loyaltyDiscountPesewas: 430,
      promoApplied: true,
      collectFromClientPesewas: 0,
      commissionPesewas: 286,
      effectiveCommissionPesewas: effectiveCommissionPesewas,
      providerSettlementBasisPesewas: settlementBasisPesewas,
      providerEarningsPesewas: providerEarningsPesewas,
      financialsFinal: financialsFinal,
      estimatedDistanceKm: 3.2,
      estimatedDurationMins: 10,
      paymentMethod: 'cash',
      createdAt: DateTime.utc(2026, 8, 15, 9),
      completedAt: DateTime.utc(2026, 8, 15, 9, 10),
    );

void main() {
  testWidgets(
      'active cash promo panel shows full fare and cash to collect details',
      (tester) async {
    final ride = _promoRide();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ProviderActiveRideFarePanel(
              fareCopy: providerActiveRideFareCopy(ride),
            ),
          ),
        ),
      ),
    );

    expect(find.text('EST. FULL FARE'), findsOneWidget);
    expect(find.text('GHS 14.30'), findsOneWidget);
    expect(find.text('PROMO / DISCOUNT'), findsOneWidget);
    expect(find.text('- GHS 14.30'), findsOneWidget);
    expect(find.text('COLLECT FROM CLIENT'), findsOneWidget);
    expect(find.text('GHS 0.00'), findsOneWidget);
  });

  testWidgets('Recent Activity uses the provider full fare for a promo ride',
      (tester) async {
    final ride = _promoRide();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driverTripsProvider.overrideWith((_) async => [ride]),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RecentActivitySection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GHS 14.30'), findsOneWidget);
    expect(find.text('GHS 4.30'), findsNothing);
    expect(find.text('GHS 0.00'), findsNothing);
  });

  test('completion uses effective commission, loyalty and server earnings', () {
    final summary = providerTripSummaryFromRide(_promoRide());

    expect(summary.totalFarePesewas, 1430);
    expect(summary.promoPesewas, 1000);
    expect(summary.loyaltyPesewas, 430);
    expect(summary.collectFromClientPesewas, 0);
    expect(summary.commissionPesewas, 186);
    expect(summary.commissionLabel, 'Effective Platform Commission');
    expect(summary.netEarningsPesewas, 1244);
    expect(summary.providerSettlementBasisPesewas, 1430);
    expect(summary.hasRefundAdjustedSettlement, isFalse);
  });

  test('completion keeps both settlement amounts pending when non-final', () {
    final summary = providerTripSummaryFromRide(
      _promoRide(financialsFinal: false),
    );

    expect(summary.commissionPesewas, isNull);
    expect(summary.netEarningsPesewas, isNull);
    expect(summary.commissionDisplay, 'Pending');
    expect(summary.netEarningsDisplay, 'Pending');
  });

  test('completion labels a partial-refund settlement basis', () {
    final summary = providerTripSummaryFromRide(
      _promoRide(
        settlementBasisPesewas: 800,
        effectiveCommissionPesewas: 100,
        providerEarningsPesewas: 700,
      ),
    );

    expect(summary.totalFarePesewas, 1430);
    expect(summary.providerSettlementBasisPesewas, 800);
    expect(summary.hasRefundAdjustedSettlement, isTrue);
    expect(summary.commissionPesewas, 100);
    expect(summary.netEarningsPesewas, 700);
  });

  test('completion accepts a conserved full-refund zero settlement', () {
    final summary = providerTripSummaryFromRide(
      _promoRide(
        settlementBasisPesewas: 0,
        effectiveCommissionPesewas: 0,
        providerEarningsPesewas: 0,
      ),
    );

    expect(summary.providerSettlementBasisPesewas, 0);
    expect(summary.hasRefundAdjustedSettlement, isTrue);
    expect(summary.commissionDisplay, 'GHS 0.00');
    expect(summary.netEarningsDisplay, 'GHS 0.00');
  });

  testWidgets('completion renders refund basis without full-fare earnings copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completed = _promoRide(
      id: '',
      settlementBasisPesewas: 800,
      effectiveCommissionPesewas: 100,
      providerEarningsPesewas: 700,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeRideProvider.overrideWith(
            (ref) => _SeededActiveRideNotifier(ref, completed),
          ),
        ],
        child: const MaterialApp(home: DriverRideCompleteScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Settlement Basis'), findsOneWidget);
    expect(find.text('GHS 8.00'), findsOneWidget);
    expect(
      find.text(
        'MyShop covers promo and loyalty discounts. Refund-adjusted earnings '
        'use the retained settlement basis shown below.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'MyShop covers promo and loyalty discounts. Your earnings are based '
        'on the full trip fare.',
      ),
      findsNothing,
    );
  });
}
