import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/widgets/fare_breakdown_card.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  testWidgets('promo, loyalty, and toll rows reconcile to the inclusive total',
      (tester) async {
    const driver = MatchedDriver(
      name: 'Kofi Driver',
      vehicle: 'Toyota Vitz',
      plateNumber: 'AS-1234-26',
      rating: 4.8,
      minutesAway: 3,
      driversAvailable: 1,
      baseFarePesewas: 1000,
      distanceFarePesewas: 3000,
      promoDiscountPesewas: 800,
      loyaltyDiscountPesewas: 200,
      toll: RideToll(
        label: 'Airport access charge',
        amountPesewas: 500,
      ),
      confirmedFarePesewas: 3500,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FareBreakdownCard(driver: driver)),
      ),
    );

    expect(driver.totalFarePesewas, 3500);
    expect(find.text('Airport access charge'), findsOneWidget);
    expect(find.text('Promotional discount'), findsOneWidget);
    expect(find.text('Loyalty discount'), findsOneWidget);
    expect(find.text('GH₵ 35.00'), findsOneWidget);
  });

  testWidgets('unaffected ride shows no toll wording', (tester) async {
    const driver = MatchedDriver(
      name: 'Kofi Driver',
      vehicle: 'Toyota Vitz',
      plateNumber: 'AS-1234-26',
      rating: 4.8,
      minutesAway: 3,
      driversAvailable: 1,
      distanceFarePesewas: 4000,
      confirmedFarePesewas: 4000,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FareBreakdownCard(driver: driver)),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.toLowerCase().contains('toll') ?? false),
      ),
      findsNothing,
    );
  });
}
