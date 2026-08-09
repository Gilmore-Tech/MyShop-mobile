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

Future<void> _pumpAction(
  WidgetTester tester, {
  required EarningsSummary? summary,
  bool refreshing = false,
  bool hasError = false,
  ValueChanged<int>? onPayCommission,
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
