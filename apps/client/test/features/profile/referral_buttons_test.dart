import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/profile/screens/referral_screen.dart';

void main() {
  testWidgets('release containment exposes no referral code or share action', (
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
    expect(find.text('Copy Code'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(find.textContaining('Existing referral records'), findsOneWidget);
  });
}
