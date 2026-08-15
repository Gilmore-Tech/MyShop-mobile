import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/earnings/providers/earnings_providers.dart';
import 'package:myshop_provider/src/features/earnings/widgets/request_payout_sheet.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

class _FakePaymentService extends PaymentService {
  _FakePaymentService({
    required this.postStatus,
    this.polledStatus,
    this.postOutcomes = const <Object>[],
  }) : super(Dio());

  final ProviderWithdrawalStatus postStatus;
  final ProviderWithdrawalStatus? polledStatus;
  final List<Object> postOutcomes;
  final List<int> expectedAmounts = <int>[];
  final List<String> idempotencyKeys = <String>[];
  int statusReads = 0;

  @override
  Future<ProviderWithdrawalStatus> withdrawProviderEarnings({
    required int expectedWithdrawablePesewas,
    required String idempotencyKey,
  }) async {
    expectedAmounts.add(expectedWithdrawablePesewas);
    idempotencyKeys.add(idempotencyKey);
    final index = expectedAmounts.length - 1;
    if (index < postOutcomes.length) {
      final outcome = postOutcomes[index];
      if (outcome is ProviderWithdrawalStatus) return outcome;
      throw outcome;
    }
    return postStatus;
  }

  @override
  Future<ProviderWithdrawalStatus> getProviderWithdrawalStatus(
    String withdrawalId,
  ) async {
    statusReads += 1;
    return polledStatus ?? postStatus;
  }
}

const _queuedWithdrawal = ProviderWithdrawalStatus(
  withdrawalId: 'withdrawal-1',
  status: ProviderWithdrawalGroupStatus.queued,
  rawStatus: 'queued',
  currency: 'GHS',
  selectedEarningsPesewas: 2100,
  deductionsAppliedPesewas: 600,
  transferQueuedPesewas: 1500,
  remainingDebtPesewas: 0,
  paymentCount: 1,
  payoutIds: <String>['payout-1'],
);

const _completedWithdrawal = ProviderWithdrawalStatus(
  withdrawalId: 'withdrawal-1',
  status: ProviderWithdrawalGroupStatus.completed,
  rawStatus: 'completed',
  currency: 'GHS',
  selectedEarningsPesewas: 2100,
  deductionsAppliedPesewas: 600,
  transferQueuedPesewas: 1500,
  remainingDebtPesewas: 0,
  paymentCount: 1,
  payoutIds: <String>['payout-1'],
);

const _reversedWithdrawal = ProviderWithdrawalStatus(
  withdrawalId: 'withdrawal-1',
  status: ProviderWithdrawalGroupStatus.needsReview,
  rawStatus: 'needs_review',
  currency: 'GHS',
  selectedEarningsPesewas: 2100,
  deductionsAppliedPesewas: 600,
  transferQueuedPesewas: 1500,
  remainingDebtPesewas: 0,
  paymentCount: 1,
  payoutIds: <String>['payout-1'],
  reviewReason: ProviderWithdrawalReviewReason.transferReversed,
);

const _boundDriver = AuthUser(
  id: 'driver-1',
  phone: '+233241234567',
  fullName: 'Driver One',
  role: AuthRole.driver,
  driverProfile: DriverProfile(
    id: 'driver-1',
    verificationStatus: 'approved',
    kycStatus: 'verified',
    policeCheckStatus: 'approved',
    onlineStatus: 'offline',
    serviceRadiusKm: 5,
    payoutPreference: 'standard',
    cancellationCount30d: 0,
    ghanaCardVerified: true,
    languagePref: 'en',
    payoutMethod: 'momo_mtn',
    payoutAccountNumber: '0241234567',
    payoutLocked: true,
  ),
);

Future<void> _openWithdrawalSheet(
  WidgetTester tester,
  _FakePaymentService fake, {
  VoidCallback? onInvalidate,
  int expectedWithdrawablePesewas = 1500,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentServiceProvider.overrideWithValue(fake),
        currentUserProvider.overrideWithValue(_boundDriver),
        providerTypeProvider.overrideWith((ref) => ProviderType.driver),
        payoutsProvider.overrideWith((ref) async => const []),
        invalidateEarningsCachesProvider.overrideWithValue(
          onInvalidate ?? () {},
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showWithdrawEarningsSheet(
                context,
                expectedWithdrawablePesewas: expectedWithdrawablePesewas,
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
  test('only an identified queued payout response is authoritative', () {
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'processing', 'payoutId': 'payout-1'},
      ),
      isTrue,
    );
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'blocked_manual_review', 'payoutId': ''},
      ),
      isFalse,
    );
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'processing'},
      ),
      isFalse,
    );
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'unknown', 'payoutId': 'payout-1'},
      ),
      isFalse,
    );
  });

  testWidgets(
    'exact withdrawal sends server amount with idempotency and does not claim 202 is paid',
    (tester) async {
      final fake = _FakePaymentService(
        postStatus: _queuedWithdrawal,
        polledStatus: _completedWithdrawal,
      );
      await _openWithdrawalSheet(tester, fake);

      expect(find.textContaining('Request GH\u20b5 15.00'), findsOneWidget);
      await tester.tap(find.text('CONFIRM WITHDRAWAL'));
      await tester.pump();
      await tester.pump();

      expect(fake.expectedAmounts, <int>[1500]);
      expect(fake.idempotencyKeys.single, isNotEmpty);
      expect(find.text('Withdrawal request accepted'), findsOneWidget);
      expect(find.textContaining('does not mean the transfer has been paid'),
          findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(fake.statusReads, 1);
      expect(find.text('Withdrawal completed'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('sheet refuses an amount below the frozen minimum', (
    tester,
  ) async {
    var invalidations = 0;
    final fake = _FakePaymentService(postStatus: _completedWithdrawal);
    await _openWithdrawalSheet(
      tester,
      fake,
      expectedWithdrawablePesewas: 1499,
      onInvalidate: () => invalidations += 1,
    );

    await tester.tap(find.text('CONFIRM WITHDRAWAL'));
    await tester.pump();
    await tester.pump();

    expect(fake.expectedAmounts, isEmpty);
    expect(find.text('TRY AGAIN'), findsNothing);
    expect(find.text('CLOSE'), findsOneWidget);
    expect(invalidations, 1);
  });

  testWidgets('needs-review sheet explains a reversed held withdrawal', (
    tester,
  ) async {
    final fake = _FakePaymentService(postStatus: _reversedWithdrawal);
    await _openWithdrawalSheet(tester, fake);

    await tester.tap(find.text('CONFIRM WITHDRAWAL'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Withdrawal needs review'), findsOneWidget);
    expect(find.textContaining('transfer was reversed'), findsOneWidget);
    expect(find.textContaining('amount remains under review'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsNothing);
  });

  testWidgets('transport retry reuses the same withdrawal idempotency key', (
    tester,
  ) async {
    final fake = _FakePaymentService(
      postStatus: _completedWithdrawal,
      postOutcomes: const <Object>[
        NetworkException(message: 'transport interrupted'),
        _completedWithdrawal,
      ],
    );
    await _openWithdrawalSheet(tester, fake);

    await tester.tap(find.text('CONFIRM WITHDRAWAL'));
    await tester.pump();
    await tester.pump();
    expect(find.text('TRY AGAIN'), findsOneWidget);

    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    await tester.pump();

    expect(fake.expectedAmounts, <int>[1500, 1500]);
    expect(fake.idempotencyKeys, hasLength(2));
    expect(fake.idempotencyKeys[1], fake.idempotencyKeys[0]);
    expect(find.text('Withdrawal completed'), findsOneWidget);
    expect(fake.statusReads, 0, reason: 'terminal 202 replay needs no polling');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final retryCase in <({String name, Object error})>[
    (
      name: 'network ambiguity',
      error: const NetworkException(message: 'offline'),
    ),
    (
      name: 'server ambiguity',
      error: const ServerException(message: 'server error', statusCode: 503),
    ),
    (name: 'response parse ambiguity', error: const FormatException('bad')),
  ]) {
    testWidgets('${retryCase.name} offers same-key retry', (tester) async {
      var invalidations = 0;
      final fake = _FakePaymentService(
        postStatus: _completedWithdrawal,
        postOutcomes: <Object>[retryCase.error, _completedWithdrawal],
      );
      await _openWithdrawalSheet(
        tester,
        fake,
        onInvalidate: () => invalidations += 1,
      );

      await tester.tap(find.text('CONFIRM WITHDRAWAL'));
      await tester.pump();
      await tester.pump();
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(invalidations, 0);

      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump();
      await tester.pump();
      expect(fake.idempotencyKeys, hasLength(2));
      expect(fake.idempotencyKeys[1], fake.idempotencyKeys[0]);
      expect(find.text('Withdrawal completed'), findsOneWidget);
    });
  }

  for (final closeCase in <({String name, String code, int status})>[
    (
      name: 'stale balance',
      code: 'WITHDRAWABLE_BALANCE_CHANGED',
      status: 409,
    ),
    (
      name: 'withdrawal in progress',
      code: 'WITHDRAWAL_IN_PROGRESS',
      status: 409,
    ),
    (
      name: 'reconciliation required',
      code: 'RECONCILIATION_REQUIRED',
      status: 409,
    ),
    (
      name: 'destination required',
      code: 'PAYOUT_DESTINATION_REQUIRED',
      status: 422,
    ),
    (name: 'unknown client error', code: 'FUTURE_CONFLICT', status: 400),
  ]) {
    testWidgets('${closeCase.name} invalidates and is CLOSE-only', (
      tester,
    ) async {
      var invalidations = 0;
      final fake = _FakePaymentService(
        postStatus: _completedWithdrawal,
        postOutcomes: <Object>[
          ApiException(
            message: closeCase.name,
            statusCode: closeCase.status,
            errorCode: closeCase.code,
          ),
        ],
      );
      await _openWithdrawalSheet(
        tester,
        fake,
        onInvalidate: () => invalidations += 1,
      );

      await tester.tap(find.text('CONFIRM WITHDRAWAL'));
      await tester.pump();
      await tester.pump();

      expect(find.text('TRY AGAIN'), findsNothing);
      expect(find.text('CLOSE'), findsOneWidget);
      expect(invalidations, 1);
      expect(fake.idempotencyKeys, hasLength(1));
    });
  }
}
