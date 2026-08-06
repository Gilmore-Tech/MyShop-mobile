import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/earnings/widgets/pay_commission_sheet.dart';

/// The remit charge flow branches on the backend's `chargeStatus`:
/// `send_otp` must surface an OTP entry step (the code can only be forwarded
/// server-side), while `pay_offline`/`pending` go straight to the awaiting
/// screen. Regression coverage for the flow that previously assumed every
/// charge was `pay_offline`.
class _FakePaymentService extends PaymentService {
  _FakePaymentService({
    required this.remitResponse,
    this.otpResponse,
    this.statusResponse,
  }) : super(Dio());

  final Map<String, dynamic> remitResponse;
  final Map<String, dynamic>? otpResponse;
  final CashCommissionRemittanceStatus? statusResponse;

  final List<String> submittedOtps = [];
  int statusReads = 0;

  @override
  Future<Map<String, dynamic>> remitCashCommission({
    required int amountPesewas,
    required String paymentMethod,
    required String momoPhone,
  }) async {
    return remitResponse;
  }

  @override
  Future<Map<String, dynamic>> submitCashCommissionRemitOtp({
    required String remittanceId,
    required String otp,
  }) async {
    submittedOtps.add(otp);
    return otpResponse!;
  }

  @override
  Future<CashCommissionRemittanceStatus> getCashCommissionRemittanceStatus(
    String remittanceId,
  ) async {
    statusReads += 1;
    return statusResponse!;
  }
}

const _completedStatus = CashCommissionRemittanceStatus(
  remitId: 'remit-1',
  status: 'completed',
  gatewayStatus: 'success',
  amountPesewas: 2000,
  owedPesewas: 0,
);

Future<void> _openSheet(WidgetTester tester, _FakePaymentService fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentServiceProvider.overrideWithValue(fake),
        currentUserProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showPayCommissionSheet(context, owedPesewas: 2000),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();

  // Amount is prefilled; only the MoMo number needs entering.
  await tester.enterText(find.byType(TextField).last, '0241234567');
  await tester.tap(find.text('PAY COMMISSION'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'send_otp charge shows the OTP step and only polls after the code is confirmed',
    (tester) async {
      final fake = _FakePaymentService(
        remitResponse: {
          'remitId': 'remit-1',
          'chargeStatus': 'send_otp',
          'displayText':
              'Enter the one-time code sent by your mobile money provider.',
          'surplusPesewas': 0,
        },
        otpResponse: {
          'remitId': 'remit-1',
          'status': 'processing',
          'chargeStatus': 'pay_offline',
          'displayText': 'Approve the payment on your phone.',
        },
        statusResponse: _completedStatus,
      );

      await _openSheet(tester, fake);

      expect(find.text('Enter the code'), findsOneWidget);
      expect(
        fake.statusReads,
        0,
        reason: 'polling must not start while the OTP is still unconfirmed',
      );

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('CONFIRM CODE'));
      await tester.pumpAndSettle();

      expect(fake.submittedOtps, ['123456']);
      expect(fake.statusReads, greaterThan(0));
      expect(find.text('Payment confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'pay_offline charge skips the OTP step and goes straight to the prompt flow',
    (tester) async {
      final fake = _FakePaymentService(
        remitResponse: {
          'remitId': 'remit-1',
          'chargeStatus': 'pay_offline',
          'displayText': 'Approve the payment on your phone.',
          'surplusPesewas': 0,
        },
        statusResponse: _completedStatus,
      );

      await _openSheet(tester, fake);

      expect(find.text('Enter the code'), findsNothing);
      expect(fake.submittedOtps, isEmpty);
      expect(find.text('Payment confirmed'), findsOneWidget);
    },
  );
}
