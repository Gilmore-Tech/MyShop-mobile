import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/profile/screens/loyalty_points_screen.dart';
import 'package:myshop_client/src/features/profile/providers/referral_provider.dart';
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

  testWidgets('referral UI never invents sibling-role balances or history', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          referralProvider.overrideWith(
            (_) async => const ReferralData(
              code: 'MYSHOP-CLIENT',
              rewardPesewas: 500,
              totalReferrals: 0,
              pendingPesewas: 0,
              earnedPesewas: 0,
              recentReferrals: [],
            ),
          ),
        ],
        child: const MaterialApp(home: ReferralScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your client referral code'), findsOneWidget);
    expect(find.text('MYSHOP-CLIENT'), findsOneWidget);
    expect(find.text('Referrals'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('GHS 0.00'), findsOneWidget);
  });
}
