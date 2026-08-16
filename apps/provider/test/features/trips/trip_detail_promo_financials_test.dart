import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/trips/widgets/trip_detail_modal.dart';

class _SnapshotRideService extends RideService {
  _SnapshotRideService(this.snapshot) : super(Dio());

  final Map<String, dynamic> snapshot;

  @override
  Future<Map<String, dynamic>> getRide(String rideId) async => snapshot;
}

TripDetailData _trip() => const TripDetailData(
      tripId: 'TRP-PROMO123',
      rideId: 'promo-ride-123',
      status: 'Completed',
      date: '15 Aug 2026',
      timeRange: '09:00 – 09:10',
      pickupTime: '09:00',
      pickupAddress: 'KNUST Gate',
      dropoffTime: '09:10',
      dropoffAddress: 'Kejetia Market',
      distanceKm: '3.2',
      durationMins: 10,
      surgeMultiplier: '1.0x',
      baseFare: '—',
      distanceFare: '—',
      timeFare: '—',
      surgeFare: 'GHS 0.00',
      subtotal: 'GHS 14.30',
      taxes: '—',
      promoDiscount: '—',
      totalPaid: 'GHS 0.00',
      commission: 'Pending',
      paymentMethod: 'Cash',
      tripFarePesewas: 1430,
      clientPaidPesewas: 0,
      promoDiscountPesewas: 1000,
      loyaltyDiscountPesewas: 430,
    );

Map<String, dynamic> _snapshot({
  Object? financialsFinal = true,
  int providerSettlementBasisPesewas = 1430,
  int effectiveCommissionPesewas = 186,
  int providerEarningsPesewas = 1244,
}) =>
    {
      'id': 'promo-ride-123',
      'status': 'completed',
      'pickupAddress': 'KNUST Gate',
      'dropoffAddress': 'Kejetia Market',
      'pickupLat': 0,
      'pickupLng': 0,
      'dropoffLat': 0,
      'dropoffLng': 0,
      'estimatedFarePesewas': 0,
      'finalFarePesewas': 430,
      'prePromoFarePesewas': '1430',
      'totalPaidPesewas': 0,
      'collectFromClientPesewas': 0,
      'promoDiscountPesewas': '1000',
      'loyaltyDiscountPesewas': 430,
      'promoApplied': true,
      'commissionPesewas': 286,
      'effectiveCommissionPesewas': effectiveCommissionPesewas,
      'providerSettlementBasisPesewas': providerSettlementBasisPesewas,
      'providerEarningsPesewas': providerEarningsPesewas,
      'financialsFinal': financialsFinal,
      'baseFare': '700',
      'distanceFare': 730,
      'bookingFee': 0,
      'surgeMultiplier': 1,
      'paymentMethod': 'cash',
    };

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> snapshot,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rideServiceProvider.overrideWithValue(_SnapshotRideService(snapshot)),
      ],
      child: MaterialApp(
        home: Scaffold(body: TripDetailModal(trip: _trip())),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
      'detail keeps full fare separate from client payment and renders '
      'discounts plus effective settlement', (tester) async {
    await _pump(tester, snapshot: _snapshot());

    expect(find.text('Trip Fare'), findsOneWidget);
    expect(find.text('GHS 14.30'), findsOneWidget);
    expect(find.text('Promo (covered by MyShop)'), findsOneWidget);
    expect(find.text('- GHS 10'), findsOneWidget);
    expect(find.text('Loyalty (covered by MyShop)'), findsOneWidget);
    expect(find.text('- GHS 4.30'), findsOneWidget);
    expect(find.text('Collect from Client'), findsOneWidget);
    expect(find.text('GHS 0.00'), findsOneWidget);
    expect(find.text('Effective Platform Commission'), findsOneWidget);
    expect(find.text('GHS 1.86'), findsOneWidget);
    expect(find.text('Your Earnings'), findsOneWidget);
    expect(find.text('GHS 12.44'), findsOneWidget);
    expect(find.text('Settlement Basis'), findsNothing);
    expect(find.text('GHS 2.86'), findsNothing);
    expect(find.text('Total Paid'), findsNothing);
    expect(find.text('SUCCESS'), findsNothing);
  });

  testWidgets('detail renders commission and earnings together as Pending',
      (tester) async {
    await _pump(tester, snapshot: _snapshot(financialsFinal: false));

    expect(find.text('Pending'), findsNWidgets(2));
    expect(
      find.text('Final settlement figures are still being recorded.'),
      findsOneWidget,
    );
    expect(find.text('GHS 1.86'), findsNothing);
    expect(find.text('GHS 12.44'), findsNothing);
  });

  testWidgets('legacy detail totalPaid cannot replace list full fare',
      (tester) async {
    final snapshot = _snapshot()
      ..remove('prePromoFarePesewas')
      ..remove('effectiveCommissionPesewas')
      ..remove('providerSettlementBasisPesewas')
      ..remove('providerEarningsPesewas')
      ..remove('financialsFinal');
    await _pump(tester, snapshot: snapshot);

    expect(find.text('GHS 14.30'), findsOneWidget);
    expect(find.text('Trip Fare'), findsOneWidget);
  });

  testWidgets('detail fails both amounts closed when final pair does not tie',
      (tester) async {
    await _pump(
      tester,
      snapshot: _snapshot(providerEarningsPesewas: 1300),
    );

    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('GHS 1.86'), findsNothing);
    expect(find.text('GHS 13'), findsNothing);
  });

  testWidgets('present malformed finality renders both amounts Pending', (
    tester,
  ) async {
    await _pump(tester, snapshot: _snapshot(financialsFinal: 'true'));

    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('GHS 1.86'), findsNothing);
    expect(find.text('GHS 12.44'), findsNothing);
  });

  testWidgets('explicit final string money renders both amounts Pending', (
    tester,
  ) async {
    final snapshot = _snapshot()..['effectiveCommissionPesewas'] = '186';
    await _pump(tester, snapshot: snapshot);

    expect(find.text('Pending'), findsNWidgets(2));
    expect(find.text('GHS 1.86'), findsNothing);
    expect(find.text('GHS 12.44'), findsNothing);
  });

  testWidgets('detail labels a refund-adjusted settlement basis',
      (tester) async {
    await _pump(
      tester,
      snapshot: _snapshot(
        providerSettlementBasisPesewas: 800,
        effectiveCommissionPesewas: 100,
        providerEarningsPesewas: 700,
      ),
    );

    expect(find.text('Trip Fare'), findsOneWidget);
    expect(find.text('GHS 14.30'), findsOneWidget);
    expect(find.text('Settlement Basis'), findsOneWidget);
    expect(find.text('GHS 8'), findsOneWidget);
    expect(find.text('GHS 1'), findsOneWidget);
    // Client paid and provider earnings are both GH₵7.00 in this fixture.
    expect(find.text('GHS 7'), findsNWidgets(2));
    expect(
      find.textContaining('Refund-adjusted settlement'),
      findsOneWidget,
    );
    expect(
      find.text(
        'MyShop covers discounts; refund-adjusted earnings use the retained '
        'basis',
      ),
      findsOneWidget,
    );
    expect(
      find.text('MyShop covers discounts; earnings use the full fare'),
      findsNothing,
    );
    expect(find.text('Pending'), findsNothing);
  });

  testWidgets('detail renders a conserved full-refund zero settlement',
      (tester) async {
    await _pump(
      tester,
      snapshot: _snapshot(
        providerSettlementBasisPesewas: 0,
        effectiveCommissionPesewas: 0,
        providerEarningsPesewas: 0,
      ),
    );

    expect(find.text('Settlement Basis'), findsOneWidget);
    // Client paid, retained basis, commission and earnings are all zero.
    expect(find.text('GHS 0.00'), findsNWidgets(4));
    expect(find.text('Pending'), findsNothing);
    expect(
      find.textContaining('Refund-adjusted settlement'),
      findsOneWidget,
    );
  });
}
