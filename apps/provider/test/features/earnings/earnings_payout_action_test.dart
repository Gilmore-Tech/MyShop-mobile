import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/driver_home/widgets/earnings_summary_section.dart';
import 'package:myshop_provider/src/features/earnings/data/earnings_service.dart';
import 'package:myshop_provider/src/features/earnings/providers/earnings_providers.dart';
import 'package:myshop_provider/src/features/earnings/widgets/commission_card.dart';
import 'package:myshop_provider/src/features/earnings/widgets/earnings_payout_action.dart';
import 'package:shared_models/shared_models.dart';

const _manual = PayoutCapability(
  mode: PayoutCapabilityMode.manualAggregate,
  canRequest: true,
  reason: PayoutCapabilityReason.manualPayoutAvailable,
  rawReasonCode: 'MANUAL_PAYOUT_AVAILABLE',
);

const _automatic = PayoutCapability(
  mode: PayoutCapabilityMode.automaticExact,
  canRequest: false,
  reason: PayoutCapabilityReason.automaticPayoutActive,
  rawReasonCode: 'AUTOMATIC_PAYOUT_ACTIVE',
);

const _automaticUnavailable = PayoutCapability(
  mode: PayoutCapabilityMode.automaticExact,
  canRequest: false,
  reason: PayoutCapabilityReason.payoutRailUnavailable,
  rawReasonCode: 'PAYOUT_RAIL_UNAVAILABLE',
);

const _commissionPayment = PayoutCapability(
  mode: PayoutCapabilityMode.unavailable,
  canRequest: false,
  reason: PayoutCapabilityReason.cashCommissionCoversBalance,
  rawReasonCode: 'CASH_COMMISSION_COVERS_BALANCE',
);

class _TodayEarningsService extends EarningsService {
  _TodayEarningsService() : super(Dio());

  @override
  Future<EarningsTodayCard> getTodayCard({required EarningsRole role}) async {
    return EarningsTodayCard(
      role: role,
      date: '2026-08-09',
      bookingsCount: 1,
      hoursWorkedMinutes: 20,
      tipsEarnedPesewas: 0,
      grossEarningsPesewas: 10000,
      commissionPesewas: 1000,
      netEarningsPesewas: 9000,
    );
  }
}

EarningsSummary _summary({
  EarningsRole role = EarningsRole.driver,
  int availablePesewas = 8000,
  int owedPesewas = 0,
  int pendingPesewas = 0,
  PayoutCapability capability = _manual,
}) {
  return EarningsSummary(
    role: role,
    period: EarningsPeriod.week,
    startDate: null,
    endDate: null,
    availableBalancePesewas: availablePesewas,
    todayAvailableBalancePesewas: 8000,
    weeklyAvailableBalancePesewas: 8000,
    netEarningsPesewas: 8000,
    tipsEarnedPesewas: 0,
    paidOutPesewas: 0,
    cashCommissionOwedPesewas: owedPesewas,
    pendingPayoutsPesewas: pendingPesewas,
    series: const <EarningsSummaryPoint>[],
    granularity: EarningsGranularity.day,
    payoutCapability: capability,
  );
}

EarningsSummary _detailedSummary({
  String actionKind = 'request_withdrawal',
  int actionAmountPesewas = 5000,
  String reasonCode = 'MANUAL_WITHDRAWAL_AVAILABLE',
  int availableBeforeDeductionsPesewas = 8000,
  int? deductionsAppliedPesewas,
  int withdrawablePesewas = 5000,
  int remainingDebtPesewas = 0,
  int? cashCommissionOwedPesewas,
  Object? minimumWithdrawalPesewas = 1500,
  int pendingPesewas = 0,
  int todayEarnedPesewas = 1200,
  int periodEarnedPesewas = 5000,
}) {
  final applied = deductionsAppliedPesewas ??
      (availableBeforeDeductionsPesewas - withdrawablePesewas);
  return EarningsSummary.fromJson({
    'role': 'driver',
    'period': 'week',
    'availableBalancePesewas': withdrawablePesewas,
    'todayAvailableBalancePesewas': todayEarnedPesewas,
    'weeklyAvailableBalancePesewas': periodEarnedPesewas,
    'netEarningsPesewas': periodEarnedPesewas,
    'tipsEarnedPesewas': 0,
    'paidOutPesewas': 0,
    'cashCommissionOwedPesewas':
        cashCommissionOwedPesewas ?? remainingDebtPesewas,
    'pendingPayoutsPesewas': pendingPesewas,
    'availableBeforeDeductionsPesewas': availableBeforeDeductionsPesewas,
    'deductionsAppliedPesewas': applied,
    'withdrawableBalancePesewas': withdrawablePesewas,
    'remainingDebtPesewas': remainingDebtPesewas,
    'heldBalancePesewas': 0,
    'minimumWithdrawalPesewas': minimumWithdrawalPesewas,
    'primaryAction': {
      'kind': actionKind,
      'amountPesewas': actionAmountPesewas,
      'reasonCode': reasonCode,
    },
    'series': <dynamic>[],
    'granularity': 'day',
  });
}

Future<void> _pumpAction(
  WidgetTester tester, {
  required EarningsSummary? summary,
  bool refreshing = false,
  bool hasError = false,
  ValueChanged<int>? onPayCommission,
  ValueChanged<int>? onWithdraw,
  VoidCallback? onSetupPayoutMethod,
  VoidCallback? onRequestPayout,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EarningsPayoutAction(
          summary: summary,
          summaryRefreshing: refreshing,
          summaryHasError: hasError,
          onPayCommission: onPayCommission ?? (_) {},
          onWithdraw: onWithdraw ?? (_) {},
          onSetupPayoutMethod: onSetupPayoutMethod ?? () {},
          onRequestPayout: onRequestPayout ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Driver Today displays authoritative provider take-home',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          earningsServiceProvider.overrideWithValue(_TodayEarningsService()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: EarningsSummarySection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GH₵ 90'), findsOneWidget);
    expect(find.text('GH₵ 100'), findsNothing);
  });

  testWidgets('commission card uses effective relief-aware backend amounts',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CommissionCard(
            grossPesewas: 10000,
            commissionPesewas: 1000,
            netPesewas: 9000,
          ),
        ),
      ),
    );

    expect(find.text('Commission Charged'), findsOneWidget);
    expect(find.text('- GHS 10'), findsOneWidget);
    expect(find.text('GHS 90'), findsOneWidget);
  });

  group('Driver and Artisan cash/digital/promo payout matrix', () {
    final cases = <({
      String name,
      EarningsSummary summary,
      EarningsPayoutActionKind kind,
      int commissionOwed,
    })>[
      (
        name: 'Driver digital non-promo manual balance',
        summary: _summary(role: EarningsRole.driver),
        kind: EarningsPayoutActionKind.requestPayout,
        commissionOwed: 0,
      ),
      (
        name: 'Artisan digital promo automatic balance',
        summary: _summary(
          role: EarningsRole.artisan,
          capability: _automatic,
        ),
        kind: EarningsPayoutActionKind.automaticPayout,
        commissionOwed: 0,
      ),
      (
        name: 'Driver cash non-promo full commission debt',
        summary: _summary(
          role: EarningsRole.driver,
          availablePesewas: 3000,
          owedPesewas: 5000,
          capability: _commissionPayment,
        ),
        kind: EarningsPayoutActionKind.payCommission,
        commissionOwed: 5000,
      ),
      (
        name: 'Artisan cash promo balance does not offset durable debt',
        summary: _summary(
          role: EarningsRole.artisan,
          availablePesewas: 5000,
          owedPesewas: 5000,
          capability: _commissionPayment,
        ),
        kind: EarningsPayoutActionKind.payCommission,
        commissionOwed: 5000,
      ),
      (
        name: 'Driver settled balance has no available payout',
        summary: _summary(
          role: EarningsRole.driver,
          availablePesewas: 0,
          capability: _automatic,
        ),
        kind: EarningsPayoutActionKind.noAvailableBalance,
        commissionOwed: 0,
      ),
      (
        name: 'Artisan pending payout overrides manual authority',
        summary: _summary(role: EarningsRole.artisan, pendingPesewas: 8000),
        kind: EarningsPayoutActionKind.payoutInProgress,
        commissionOwed: 0,
      ),
    ];

    for (final testCase in cases) {
      test(testCase.name, () {
        final state = resolveEarningsPayoutAction(
          summary: testCase.summary,
          summaryRefreshing: false,
          summaryHasError: false,
        );

        expect(state.kind, testCase.kind);
        expect(state.commissionOwedPesewas, testCase.commissionOwed);
      });
    }
  });

  test('missing capability fails closed despite positive balance', () {
    final state = resolveEarningsPayoutAction(
      summary: _summary(capability: const PayoutCapability.unavailable()),
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
    expect(state.isActionable, isFalse);
  });

  test('automatic mode with unavailable rail fails closed', () {
    final state = resolveEarningsPayoutAction(
      summary: _summary(capability: _automaticUnavailable),
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
    expect(state.isActionable, isFalse);
  });

  test('missing capability also fences a legacy negative balance', () {
    final state = resolveEarningsPayoutAction(
      summary: _summary(
        availablePesewas: 3000,
        owedPesewas: 5000,
        capability: const PayoutCapability.unavailable(),
      ),
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
    expect(state.isActionable, isFalse);
  });

  test('missing capability fences debt even when available balance is larger',
      () {
    final state = resolveEarningsPayoutAction(
      summary: _summary(
        availablePesewas: 8000,
        owedPesewas: 5000,
        capability: const PayoutCapability.unavailable(),
      ),
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
    expect(state.isActionable, isFalse);
  });

  test('loading and error states fence both provider roles', () {
    for (final role in EarningsRole.values) {
      expect(
        resolveEarningsPayoutAction(
          summary: _summary(role: role),
          summaryRefreshing: true,
          summaryHasError: false,
        ).kind,
        EarningsPayoutActionKind.refreshingBalance,
      );
      expect(
        resolveEarningsPayoutAction(
          summary: _summary(role: role),
          summaryRefreshing: false,
          summaryHasError: true,
        ).kind,
        EarningsPayoutActionKind.payoutUnavailable,
      );
    }
  });

  testWidgets('manual request is the only actionable payout button', (
    tester,
  ) async {
    var requests = 0;
    await _pumpAction(
      tester,
      summary: _summary(),
      onRequestPayout: () => requests += 1,
    );

    expect(find.byKey(const Key('earnings-request-payout')), findsOneWidget);
    expect(find.text('REQUEST PAYOUT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('earnings-request-payout')));
    expect(requests, 1);

    await _pumpAction(tester, summary: _summary(capability: _automatic));
    expect(find.byKey(const Key('earnings-request-payout')), findsNothing);
    expect(find.byKey(const Key('earnings-payout-status')), findsOneWidget);
    expect(find.text('AUTOMATIC PAYOUT'), findsOneWidget);
  });

  testWidgets('legacy payout respects the frozen GHS15 minimum', (
    tester,
  ) async {
    var requests = 0;
    await _pumpAction(
      tester,
      summary: _summary(availablePesewas: 1499),
      onRequestPayout: () => requests += 1,
    );

    expect(find.text('BELOW WITHDRAWAL MINIMUM'), findsOneWidget);
    expect(find.textContaining('GHS 15.00 minimum'), findsOneWidget);
    expect(find.byKey(const Key('earnings-request-payout')), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(requests, 0);

    await _pumpAction(
      tester,
      summary: _summary(availablePesewas: 1500),
      onRequestPayout: () => requests += 1,
    );
    expect(find.byKey(const Key('earnings-request-payout')), findsOneWidget);
  });

  testWidgets('explicit request_withdrawal renders a real WITHDRAW button', (
    tester,
  ) async {
    int? requestedAmount;
    await _pumpAction(
      tester,
      summary: _detailedSummary(),
      onWithdraw: (amount) => requestedAmount = amount,
    );

    expect(find.byKey(const Key('earnings-withdraw')), findsOneWidget);
    expect(find.text('WITHDRAW'), findsOneWidget);
    expect(find.byKey(const Key('earnings-request-payout')), findsNothing);
    await tester.tap(find.byKey(const Key('earnings-withdraw')));
    expect(requestedAmount, 5000);
  });

  test('explicit unknown action never falls back to legacy capability', () {
    final json = {
      'role': 'driver',
      'period': 'week',
      'availableBalancePesewas': 5000,
      'todayAvailableBalancePesewas': 0,
      'weeklyAvailableBalancePesewas': 0,
      'netEarningsPesewas': 0,
      'tipsEarnedPesewas': 0,
      'paidOutPesewas': 0,
      'cashCommissionOwedPesewas': 0,
      'pendingPayoutsPesewas': 0,
      'availableBeforeDeductionsPesewas': 5000,
      'deductionsAppliedPesewas': 0,
      'withdrawableBalancePesewas': 5000,
      'remainingDebtPesewas': 0,
      'heldBalancePesewas': 0,
      'primaryAction': {
        'kind': 'future_withdrawal',
        'amountPesewas': 5000,
        'reasonCode': 'FUTURE_REASON',
      },
      'payoutCapability': {
        'mode': 'manual_aggregate',
        'canRequest': true,
        'reasonCode': 'MANUAL_PAYOUT_AVAILABLE',
      },
      'series': <dynamic>[],
      'granularity': 'day',
    };
    final state = resolveEarningsPayoutAction(
      summary: EarningsSummary.fromJson(json),
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
    expect(state.isActionable, isFalse);
  });

  test(
    'withdraw amount mismatch and precedence contradictions fail closed',
    () {
      expect(
        resolveEarningsPayoutAction(
          summary: _detailedSummary(actionAmountPesewas: 4999),
          summaryRefreshing: false,
          summaryHasError: false,
        ).kind,
        EarningsPayoutActionKind.payoutUnavailable,
      );
      expect(
        resolveEarningsPayoutAction(
          summary: _detailedSummary(
            availableBeforeDeductionsPesewas: 1000,
            deductionsAppliedPesewas: 0,
            withdrawablePesewas: 1000,
            actionAmountPesewas: 1000,
          ),
          summaryRefreshing: false,
          summaryHasError: false,
        ).kind,
        EarningsPayoutActionKind.payoutUnavailable,
        reason: 'withdrawable must reach the frozen GHS15 minimum',
      );
      expect(
        resolveEarningsPayoutAction(
          summary: _detailedSummary(minimumWithdrawalPesewas: 1400),
          summaryRefreshing: false,
          summaryHasError: false,
        ).kind,
        EarningsPayoutActionKind.payoutUnavailable,
        reason: 'the server minimum must match the frozen 1500-pesewa value',
      );
      expect(
        resolveEarningsPayoutAction(
          summary: _detailedSummary(remainingDebtPesewas: 1000),
          summaryRefreshing: false,
          summaryHasError: false,
        ).kind,
        EarningsPayoutActionKind.payoutUnavailable,
      );
      final contradictory = _detailedSummary(
        withdrawablePesewas: 400,
        remainingDebtPesewas: 500,
        actionAmountPesewas: 400,
      );
      expect(contradictory.hasAuthoritativeBalanceBreakdown, isFalse);
      expect(
        resolveEarningsPayoutAction(
          summary: contradictory,
          summaryRefreshing: false,
          summaryHasError: false,
        ).kind,
        EarningsPayoutActionKind.payoutUnavailable,
      );
    },
  );

  test('none reason codes render distinct truthful status states', () {
    final cases = <(String, EarningsPayoutActionKind, String)>[
      ('HOLD_ACTIVE', EarningsPayoutActionKind.holdActive, 'EARNINGS ON HOLD'),
      (
        'BELOW_MINIMUM',
        EarningsPayoutActionKind.belowMinimum,
        'BELOW WITHDRAWAL MINIMUM',
      ),
      (
        'NO_WITHDRAWABLE_BALANCE',
        EarningsPayoutActionKind.noAvailableBalance,
        'NO WITHDRAWABLE BALANCE',
      ),
      (
        'AUTOMATIC_PAYOUT_ACTIVE',
        EarningsPayoutActionKind.automaticPayout,
        'AUTOMATIC PAYOUT ACTIVE',
      ),
    ];
    for (final (reason, kind, label) in cases) {
      final state = resolveEarningsPayoutAction(
        summary: _detailedSummary(
          actionKind: 'none',
          actionAmountPesewas: 0,
          reasonCode: reason,
          withdrawablePesewas: 0,
        ),
        summaryRefreshing: false,
        summaryHasError: false,
      );
      expect(state.kind, kind);
      expect(state.label, label);
      expect(state.isActionable, isFalse);
    }
  });

  test('below-minimum copy uses the exact server minimum and shortfall', () {
    final state = resolveEarningsPayoutAction(
      summary: _detailedSummary(
        actionKind: 'none',
        actionAmountPesewas: 0,
        reasonCode: 'BELOW_MINIMUM',
        availableBeforeDeductionsPesewas: 400,
        deductionsAppliedPesewas: 0,
        withdrawablePesewas: 400,
        minimumWithdrawalPesewas: 1500,
      ),
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(state.kind, EarningsPayoutActionKind.belowMinimum);
    expect(state.description, contains('GHS 15.00 minimum'));
    expect(
      state.description,
      contains('GHS 11.00 more must become withdrawable'),
    );
  });

  testWidgets('below-minimum status renders GHS15 and the exact gap', (
    tester,
  ) async {
    await _pumpAction(
      tester,
      summary: _detailedSummary(
        actionKind: 'none',
        actionAmountPesewas: 0,
        reasonCode: 'BELOW_MINIMUM',
        availableBeforeDeductionsPesewas: 400,
        deductionsAppliedPesewas: 0,
        withdrawablePesewas: 400,
        minimumWithdrawalPesewas: 1500,
      ),
    );

    expect(find.textContaining('GHS 15.00 minimum'), findsOneWidget);
    expect(
      find.textContaining('GHS 11.00 more must become withdrawable'),
      findsOneWidget,
    );
    expect(find.byType(ElevatedButton), findsNothing);
  });

  test('below-minimum action fails closed without a valid server minimum', () {
    for (final minimum in <Object?>[null, '1500', 0, -1, 1400, 1600]) {
      final state = resolveEarningsPayoutAction(
        summary: _detailedSummary(
          actionKind: 'none',
          actionAmountPesewas: 0,
          reasonCode: 'BELOW_MINIMUM',
          availableBeforeDeductionsPesewas: 400,
          deductionsAppliedPesewas: 0,
          withdrawablePesewas: 400,
          minimumWithdrawalPesewas: minimum,
        ),
        summaryRefreshing: false,
        summaryHasError: false,
      );
      expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
    }
  });

  test('cash commission contradiction fences an explicit withdrawal', () {
    final summary = _detailedSummary(
      cashCommissionOwedPesewas: 1,
      remainingDebtPesewas: 0,
    );

    expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
    expect(
      resolveEarningsPayoutAction(
        summary: summary,
        summaryRefreshing: false,
        summaryHasError: false,
      ).kind,
      EarningsPayoutActionKind.payoutUnavailable,
    );
  });

  test('pay_remaining_commission requires all remaining debt to be cash owed',
      () {
    final state = resolveEarningsPayoutAction(
      summary: _detailedSummary(
        actionKind: 'pay_remaining_commission',
        actionAmountPesewas: 500,
        reasonCode: 'OUTSTANDING_DEDUCTIONS',
        availableBeforeDeductionsPesewas: 1000,
        deductionsAppliedPesewas: 1000,
        withdrawablePesewas: 0,
        remainingDebtPesewas: 500,
        cashCommissionOwedPesewas: 300,
      ),
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
  });

  test('malformed-present additive contract never uses legacy payout fallback',
      () {
    final summary = EarningsSummary.fromJson({
      'role': 'driver',
      'period': 'week',
      'availableBalancePesewas': 5000,
      'todayAvailableBalancePesewas': 0,
      'weeklyAvailableBalancePesewas': 0,
      'netEarningsPesewas': 0,
      'tipsEarnedPesewas': 0,
      'paidOutPesewas': 0,
      'cashCommissionOwedPesewas': 0,
      'pendingPayoutsPesewas': 0,
      'withdrawableBalancePesewas': '5000',
      'payoutCapability': {
        'mode': 'manual_aggregate',
        'canRequest': true,
        'reasonCode': 'MANUAL_PAYOUT_AVAILABLE',
      },
      'series': <dynamic>[],
      'granularity': 'day',
    });
    final state = resolveEarningsPayoutAction(
      summary: summary,
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(summary.hasBalanceBreakdownContract, isTrue);
    expect(state.kind, EarningsPayoutActionKind.payoutUnavailable);
  });

  test('malformed cash or pending values fence legacy payout authority', () {
    for (final field in <String>[
      'cashCommissionOwedPesewas',
      'pendingPayoutsPesewas',
    ]) {
      final summary = EarningsSummary.fromJson({
        'role': 'driver',
        'period': 'week',
        'availableBalancePesewas': 5000,
        'todayAvailableBalancePesewas': 0,
        'weeklyAvailableBalancePesewas': 0,
        'netEarningsPesewas': 0,
        'tipsEarnedPesewas': 0,
        'paidOutPesewas': 0,
        'cashCommissionOwedPesewas': 0,
        'pendingPayoutsPesewas': 0,
        field: '0',
        'payoutCapability': {
          'mode': 'manual_aggregate',
          'canRequest': true,
          'reasonCode': 'MANUAL_PAYOUT_AVAILABLE',
        },
        'series': <dynamic>[],
        'granularity': 'day',
      });

      expect(
        resolveEarningsPayoutAction(
          summary: summary,
          summaryRefreshing: false,
          summaryHasError: false,
        ).kind,
        EarningsPayoutActionKind.payoutUnavailable,
      );
    }
  });

  testWidgets('A21 applied6 W15 renders WITHDRAW at the exact minimum',
      (tester) async {
    int? requestedAmount;
    final summary = _detailedSummary(
      availableBeforeDeductionsPesewas: 2100,
      deductionsAppliedPesewas: 600,
      withdrawablePesewas: 1500,
      actionAmountPesewas: 1500,
    );

    await _pumpAction(
      tester,
      summary: summary,
      onWithdraw: (amount) => requestedAmount = amount,
    );

    await tester.tap(find.byKey(const Key('earnings-withdraw')));
    expect(requestedAmount, 1500);
    expect(summary.withdrawableBalancePesewas, 1500);
  });

  testWidgets('fully applied balance leaves GH₵5 debt and Pay Commission',
      (tester) async {
    int? commissionAmount;
    final summary = _detailedSummary(
      availableBeforeDeductionsPesewas: 1000,
      deductionsAppliedPesewas: 1000,
      withdrawablePesewas: 0,
      remainingDebtPesewas: 500,
      actionKind: 'pay_remaining_commission',
      actionAmountPesewas: 500,
      reasonCode: 'OUTSTANDING_DEDUCTIONS',
    );

    await _pumpAction(
      tester,
      summary: summary,
      onPayCommission: (amount) => commissionAmount = amount,
    );

    expect(find.byKey(const Key('earnings-withdraw')), findsNothing);
    await tester.tap(find.byKey(const Key('earnings-pay-commission')));
    expect(commissionAmount, 500);
    expect(summary.remainingDebtPesewas, 500);
  });

  test('promo equal to commission keeps earned80 but no withdrawal or debt',
      () {
    final summary = _detailedSummary(
      availableBeforeDeductionsPesewas: 0,
      deductionsAppliedPesewas: 0,
      withdrawablePesewas: 0,
      remainingDebtPesewas: 0,
      actionKind: 'none',
      actionAmountPesewas: 0,
      reasonCode: 'NO_WITHDRAWABLE_BALANCE',
      todayEarnedPesewas: 8000,
      periodEarnedPesewas: 8000,
    );
    final state = resolveEarningsPayoutAction(
      summary: summary,
      summaryRefreshing: false,
      summaryHasError: false,
    );

    expect(summary.todayAvailableBalancePesewas, 8000);
    expect(summary.withdrawableBalancePesewas, 0);
    expect(summary.remainingDebtPesewas, 0);
    expect(state.kind, EarningsPayoutActionKind.noAvailableBalance);
    expect(state.isActionable, isFalse);
  });

  testWidgets('pending withdrawal hides WITHDRAW and shows progress',
      (tester) async {
    await _pumpAction(
      tester,
      summary: _detailedSummary(
        availableBeforeDeductionsPesewas: 1000,
        deductionsAppliedPesewas: 600,
        withdrawablePesewas: 400,
        pendingPesewas: 400,
        actionKind: 'payout_in_progress',
        actionAmountPesewas: 400,
        reasonCode: 'PAYOUT_IN_PROGRESS',
      ),
    );

    expect(find.byKey(const Key('earnings-withdraw')), findsNothing);
    expect(find.text('PAYOUT IN PROGRESS'), findsOneWidget);
    expect(find.byKey(const Key('earnings-payout-status')), findsOneWidget);
  });

  testWidgets('Pay Commission passes the full durable debt', (
    tester,
  ) async {
    int? receivedArrears;
    await _pumpAction(
      tester,
      summary: _summary(
        availablePesewas: 3000,
        owedPesewas: 5000,
        capability: _commissionPayment,
      ),
      onPayCommission: (value) => receivedArrears = value,
    );

    await tester.tap(find.byKey(const Key('earnings-pay-commission')));
    expect(receivedArrears, 5000);
  });

  testWidgets('pending, zero, loading and error are status-only', (
    tester,
  ) async {
    final cases = <({
      EarningsSummary? summary,
      bool refreshing,
      bool hasError,
      String label,
    })>[
      (
        summary: _summary(pendingPesewas: 8000),
        refreshing: false,
        hasError: false,
        label: 'PAYOUT IN PROGRESS',
      ),
      (
        summary: _summary(availablePesewas: 0),
        refreshing: false,
        hasError: false,
        label: 'NO AVAILABLE BALANCE',
      ),
      (
        summary: _summary(),
        refreshing: true,
        hasError: false,
        label: 'REFRESHING BALANCE',
      ),
      (
        summary: _summary(),
        refreshing: false,
        hasError: true,
        label: 'PAYOUT UNAVAILABLE',
      ),
    ];

    for (final testCase in cases) {
      await _pumpAction(
        tester,
        summary: testCase.summary,
        refreshing: testCase.refreshing,
        hasError: testCase.hasError,
      );
      expect(find.text(testCase.label), findsOneWidget);
      expect(find.byKey(const Key('earnings-payout-status')), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    }
  });
}
