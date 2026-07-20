import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/profile/screens/loyalty_points_screen.dart';
import 'package:myshop_client/src/features/profile/screens/referral_screen.dart';

void main() {
  testWidgets('paused shared loyalty ledger exposes no balance or history', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoyaltyPointsScreen()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Loyalty programme temporarily paused'),
      findsOneWidget,
    );
    expect(find.text('0'), findsNothing);
    expect(find.text('points available'), findsNothing);
    expect(find.text('Transaction History'), findsNothing);
  });

  testWidgets('referral release containment exposes no ledger or zero stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ReferralScreen()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Referral programme temporarily paused'),
      findsOneWidget,
    );
    expect(find.text('Total Referrals'), findsNothing);
    expect(find.text('GHS 0.00'), findsNothing);
  });
}
