import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/loyalty/domain/loyalty_models.dart';
import 'package:myshop_client/src/features/loyalty/providers/loyalty_redemption_providers.dart';
import 'package:myshop_client/src/features/loyalty/widgets/apply_loyalty_points_row.dart';

Future<ProviderContainer> _pumpRow(
  WidgetTester tester, {
  required int balance,
  LoyaltyRedemption? applied,
  String bookingId = 'r1',
}) async {
  final container = ProviderContainer(
    overrides: [loyaltyBalanceProvider.overrideWithValue(balance)],
  );
  addTearDown(container.dispose);
  if (applied != null) {
    container.read(appliedRedemptionProvider(bookingId).notifier).state =
        applied;
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: ApplyLoyaltyPointsRow(
            bookingType: RedeemableBookingType.ride,
            bookingId: bookingId,
            farePesewas: 5000,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('hides entirely when the client has no points', (tester) async {
    await _pumpRow(tester, balance: 0);
    expect(find.text('Apply loyalty points'), findsNothing);
  });

  testWidgets('offers the redeem entry when points are available',
      (tester) async {
    await _pumpRow(tester, balance: 240);
    expect(find.text('Apply loyalty points'), findsOneWidget);
    expect(find.textContaining('240 points available'), findsOneWidget);
  });

  testWidgets('shows the applied discount line once redeemed', (tester) async {
    await _pumpRow(
      tester,
      balance: 240,
      applied: const LoyaltyRedemption(
        pointsRedeemed: 150,
        discountPesewas: 1500,
        newBalance: 90,
      ),
    );
    // Entry control is gone; the applied line takes its place (one per booking).
    expect(find.text('Apply loyalty points'), findsNothing);
    expect(find.textContaining('150 pts'), findsOneWidget);
    expect(find.text('-GHS 15.00'), findsOneWidget);
  });
}
