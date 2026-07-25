import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/profile/providers/referral_provider.dart';
import 'package:myshop_client/src/features/profile/screens/referral_screen.dart';

void main() {
  testWidgets('shows only the client role code with copy and share actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          referralProvider.overrideWith(
            (_) async => const ReferralData(
              code: 'MYSHOP-ABC123',
              shareLink: 'myshop://referral?code=MYSHOP-ABC123',
              rewardPesewas: 500,
              totalReferrals: 2,
              pendingPesewas: 500,
              earnedPesewas: 500,
              recentReferrals: [],
            ),
          ),
        ],
        child: const MaterialApp(home: ReferralScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your client referral code'), findsOneWidget);
    expect(find.text('MYSHOP-ABC123'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('GHS 5.00'), findsOneWidget);
  });
}
