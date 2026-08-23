import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/earnings/providers/earnings_providers.dart';
import 'package:myshop_provider/src/features/earnings/services/cash_commission_remittance_poller.dart';
import 'package:myshop_provider/src/features/earnings/widgets/pay_commission_sheet.dart';

/// The remit charge flow branches on the backend's `chargeStatus`:
/// `send_otp` must surface an OTP entry step (the code can only be forwarded
/// server-side), while `pay_offline`/`pending` go straight to the awaiting
/// screen. Regression coverage for the flow that previously assumed every
/// charge was `pay_offline`.
class _FakePaymentService extends PaymentService {
  _FakePaymentService({
    required this.remitResponse,
    this.remitOutcomes = const [],
    this.otpResponse,
    this.statusResponse,
  }) : super(Dio());

  final Map<String, dynamic> remitResponse;
  final List<Object> remitOutcomes;
  final Map<String, dynamic>? otpResponse;
  final CashCommissionRemittanceStatus? statusResponse;

  final List<String> submittedOtps = [];
  final List<String> remitIdempotencyKeys = [];
  final List<int> remitAmounts = [];
  int statusReads = 0;

  @override
  Future<Map<String, dynamic>> remitCashCommission({
    required int amountPesewas,
    required String paymentMethod,
    required String momoPhone,
    required String idempotencyKey,
  }) async {
    remitAmounts.add(amountPesewas);
    remitIdempotencyKeys.add(idempotencyKey);
    final callIndex = remitIdempotencyKeys.length - 1;
    final outcome = callIndex < remitOutcomes.length
        ? remitOutcomes[callIndex]
        : remitResponse;
    if (outcome is Map<String, dynamic>) return outcome;
    throw outcome;
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

const _processingStatus = CashCommissionRemittanceStatus(
  remitId: 'remit-1',
  status: 'processing',
  gatewayStatus: 'pending',
  amountPesewas: 2000,
  owedPesewas: 2000,
);

Future<void> _openSheet(
  WidgetTester tester,
  _FakePaymentService fake, {
  CashCommissionRemittancePoller poller =
      const CashCommissionRemittancePoller(),
  VoidCallback? onInvalidate,
  bool settleAfterSubmit = true,
}) async {
  await _showSheet(
    tester,
    fake,
    poller: poller,
    onInvalidate: onInvalidate,
  );

  // Amount is prefilled; only the MoMo number needs entering.
  await tester.enterText(find.byType(TextField).last, '0241234567');
  await tester.tap(find.text('PAY COMMISSION'));
  if (settleAfterSubmit) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _showSheet(
  WidgetTester tester,
  _FakePaymentService fake, {
  CashCommissionRemittancePoller poller =
      const CashCommissionRemittancePoller(),
  VoidCallback? onInvalidate,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentServiceProvider.overrideWithValue(fake),
        currentUserProvider.overrideWithValue(null),
        if (onInvalidate != null)
          invalidateEarningsCachesProvider.overrideWithValue(onInvalidate),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPayCommissionSheet(
                context,
                owedPesewas: 2000,
                poller: poller,
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('poll timeout refreshes once and gives truthful recovery copy', (
    tester,
  ) async {
    var invalidations = 0;
    final fake = _FakePaymentService(
      remitResponse: {
        'remitId': 'remit-1',
        'chargeStatus': 'pay_offline',
        'displayText': 'Approve the payment on your phone.',
      },
      statusResponse: _processingStatus,
    );
    await _openSheet(
      tester,
      fake,
      poller: CashCommissionRemittancePoller(
        interval: Duration.zero,
        maxAttempts: 1,
        delay: (_) async {},
      ),
      onInvalidate: () => invalidations += 1,
      settleAfterSubmit: false,
    );

    expect(fake.statusReads, 1);
    expect(invalidations, 1);
    expect(
      find.textContaining(
        'Close this sheet and refresh Earnings to check the latest status.',
      ),
      findsOneWidget,
    );
    expect(
        find.textContaining('checking safely in the background'), findsNothing);
  });

  testWidgets(
    'send_otp charge shows the OTP step and only polls after the code is confirmed',
    (tester) async {
      final fake = _FakePaymentService(
        remitResponse: {
          'remitId': 'remit-1',
          'chargeStatus': 'send_otp',
          'displayText':
              'Enter the one-time code sent by your mobile money provider.',
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
        },
        statusResponse: _completedStatus,
      );

      await _openSheet(tester, fake);

      expect(find.text('Enter the code'), findsNothing);
      expect(fake.submittedOtps, isEmpty);
      expect(find.text('Payment confirmed'), findsOneWidget);
    },
  );

  testWidgets('rejects an amount above the balance before API transport',
      (tester) async {
    final fake = _FakePaymentService(
      remitResponse: const {
        'remitId': 'remit-1',
        'chargeStatus': 'pay_offline',
      },
    );

    await _showSheet(tester, fake);

    expect(find.textContaining('overpayment'), findsNothing);
    expect(find.textContaining('credit against your next ride'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '20.01');
    await tester.enterText(find.byType(TextField).last, '0241234567');
    await tester.tap(find.text('PAY COMMISSION'));
    await tester.pump();

    expect(fake.remitIdempotencyKeys, isEmpty);
    expect(
      find.textContaining('Enter no more than GH₵ 20'),
      findsOneWidget,
    );
  });

  testWidgets('transport retry reuses the exact remittance idempotency key',
      (tester) async {
    final success = <String, dynamic>{
      'remitId': 'remit-1',
      'chargeStatus': 'pay_offline',
      'displayText': 'Approve the payment on your phone.',
    };
    final fake = _FakePaymentService(
      remitResponse: success,
      remitOutcomes: [
        const NetworkException(message: 'Connection timed out.'),
        success,
      ],
      statusResponse: _completedStatus,
    );

    await _openSheet(tester, fake);

    expect(find.text('RETRY SAFELY'), findsOneWidget);
    expect(fake.remitIdempotencyKeys, hasLength(1));
    await tester.tap(find.text('RETRY SAFELY'));
    await tester.pumpAndSettle();

    expect(fake.remitIdempotencyKeys, hasLength(2));
    expect(
      fake.remitIdempotencyKeys[1],
      fake.remitIdempotencyKeys[0],
    );
    expect(fake.remitAmounts, [2000, 2000]);
    expect(find.text('Payment confirmed'), findsOneWidget);
  });

  testWidgets('changed remittance body receives a new idempotency key',
      (tester) async {
    final success = <String, dynamic>{
      'remitId': 'remit-1',
      'chargeStatus': 'pay_offline',
    };
    final fake = _FakePaymentService(
      remitResponse: success,
      remitOutcomes: [
        const ApiException(
          message: 'Invalid MoMo number.',
          statusCode: 400,
          errorCode: 'INVALID_MOMO_PHONE',
        ),
        success,
      ],
      statusResponse: _completedStatus,
    );

    await _openSheet(tester, fake);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.00');
    await tester.tap(find.text('PAY COMMISSION'));
    await tester.pumpAndSettle();

    expect(fake.remitIdempotencyKeys, hasLength(2));
    expect(
      fake.remitIdempotencyKeys[1],
      isNot(fake.remitIdempotencyKeys[0]),
    );
    expect(fake.remitAmounts, [2000, 1000]);
  });

  for (final errorCase in <(String, String)>[
    (
      'AMOUNT_EXCEEDS_OWED',
      'Your commission balance changed',
    ),
    (
      'CASH_COMMISSION_REMIT_IN_PROGRESS',
      'A commission payment is already in progress',
    ),
    (
      'IDEMPOTENCY_MISMATCH',
      "We couldn't safely match this request",
    ),
  ]) {
    testWidgets('${errorCase.$1} fails closed without a second charge',
        (tester) async {
      final fake = _FakePaymentService(
        remitResponse: const {},
        remitOutcomes: [
          ApiException(
            message: 'Conflict.',
            statusCode: 409,
            errorCode: errorCase.$1,
          ),
        ],
      );

      await _openSheet(tester, fake);

      expect(find.textContaining(errorCase.$2), findsOneWidget);
      expect(find.text('RETRY SAFELY'), findsNothing);
      expect(find.text('TRY AGAIN'), findsNothing);
      expect(find.text('CLOSE'), findsOneWidget);
      expect(fake.remitIdempotencyKeys, hasLength(1));
    });
  }
}
