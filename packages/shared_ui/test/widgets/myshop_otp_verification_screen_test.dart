import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('system back uses the OTP host back action', (tester) async {
    var backCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MyShopOtpVerificationScreen(
          phone: '+233 •••• •• 67',
          onVerify: (_) {},
          onResend: () {},
          onBack: () => backCalls++,
        ),
      ),
    );

    expect(
      find.text(
        'Enter the 6-digit code for +233 •••• •• 67. '
        'It may take a moment to arrive.',
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(backCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
