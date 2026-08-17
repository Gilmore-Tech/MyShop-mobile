import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/earnings/widgets/earnings_balance_breakdown_card.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

EarningsSummary _summary({
  bool detailed = true,
  int availableBeforePesewas = 8000,
  int deductionsAppliedPesewas = 3000,
  int withdrawablePesewas = 5000,
  int remainingDebtPesewas = 0,
  int heldPesewas = 1200,
  int earnedPesewas = 9000,
  int tipsPesewas = 1000,
}) {
  return EarningsSummary.fromJson({
    'role': 'driver',
    'period': 'week',
    'availableBalancePesewas': 5000,
    'todayAvailableBalancePesewas': 2000,
    'weeklyAvailableBalancePesewas': 10000,
    'netEarningsPesewas': earnedPesewas,
    'tipsEarnedPesewas': tipsPesewas,
    'paidOutPesewas': 0,
    'cashCommissionOwedPesewas': 0,
    'pendingPayoutsPesewas': 0,
    if (detailed) 'availableBeforeDeductionsPesewas': availableBeforePesewas,
    if (detailed) 'deductionsAppliedPesewas': deductionsAppliedPesewas,
    if (detailed) 'withdrawableBalancePesewas': withdrawablePesewas,
    if (detailed) 'remainingDebtPesewas': remainingDebtPesewas,
    if (detailed) 'heldBalancePesewas': heldPesewas,
    if (detailed) 'nextPayoutEligibleAt': '2026-08-15T12:30:00.000Z',
    'series': <dynamic>[],
    'granularity': 'day',
  });
}

void main() {
  testWidgets('shows each server-authored balance without local netting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EarningsBalanceBreakdownCard(summary: _summary())),
      ),
    );

    expect(find.text('Balance after deductions'), findsOneWidget);
    expect(find.text('GH₵ 50.00'), findsOneWidget);
    expect(find.text('Earned this week'), findsOneWidget);
    expect(find.text('GH₵ 100.00'), findsOneWidget);
    expect(find.text('Available before deductions'), findsOneWidget);
    expect(find.text('GH₵ 80.00'), findsOneWidget);
    expect(find.text('Deductions applied'), findsOneWidget);
    expect(find.text('− GH₵ 30.00'), findsOneWidget);
    expect(find.text('Held'), findsOneWidget);
    expect(find.text('GH₵ 12.00'), findsOneWidget);
    expect(find.text('Remaining debt'), findsOneWidget);
    expect(find.text('GH₵ 0.00'), findsOneWidget);
    expect(find.byKey(const Key('earnings-hold-explanation')), findsOneWidget);
    expect(
      find.textContaining('The next held earnings become eligible'),
      findsOneWidget,
    );
  });

  testWidgets('refuses to render a partial legacy breakdown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EarningsBalanceBreakdownCard(
            summary: _summary(detailed: false),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('earnings-authoritative-balance-card')),
      findsNothing,
    );
  });

  testWidgets('malformed additive balance renders a refresh-only card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EarningsBalanceUnavailableCard()),
      ),
    );

    expect(
      find.byKey(const Key('earnings-balance-unavailable-card')),
      findsOneWidget,
    );
    expect(find.text('Balance temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('Refresh earnings'), findsOneWidget);
    expect(find.textContaining('GH₵'), findsNothing);
  });

  testWidgets('renders A10 applied6 W4 directly from backend fields',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EarningsBalanceBreakdownCard(
            summary: _summary(
              availableBeforePesewas: 1000,
              deductionsAppliedPesewas: 600,
              withdrawablePesewas: 400,
              remainingDebtPesewas: 0,
              heldPesewas: 0,
            ),
          ),
        ),
      ),
    );

    expect(find.text('GH₵ 10.00'), findsOneWidget);
    expect(find.text('− GH₵ 6.00'), findsOneWidget);
    expect(find.text('GH₵ 4.00'), findsOneWidget);
    expect(find.text('GH₵ 0.00'), findsNWidgets(2));
  });

  testWidgets('renders fully applied balance and remaining GH₵5 debt',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EarningsBalanceBreakdownCard(
            summary: _summary(
              availableBeforePesewas: 1000,
              deductionsAppliedPesewas: 1000,
              withdrawablePesewas: 0,
              remainingDebtPesewas: 500,
              heldPesewas: 0,
            ),
          ),
        ),
      ),
    );

    expect(find.text('− GH₵ 10.00'), findsOneWidget);
    expect(find.text('GH₵ 5.00'), findsOneWidget);
    expect(find.text('− GH₵ 5.00'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const Key('earnings-balance-after-deductions-amount'),
            ),
          )
          .data,
      '− GH₵ 5.00',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const Key('earnings-balance-after-deductions-amount'),
            ),
          )
          .style
          ?.color,
      MyShopColors.error,
    );
  });

  testWidgets('can show earned today80 with zero withdrawable and debt',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EarningsBalanceBreakdownCard(
            summary: _summary(
              availableBeforePesewas: 0,
              deductionsAppliedPesewas: 0,
              withdrawablePesewas: 0,
              remainingDebtPesewas: 0,
              heldPesewas: 0,
              earnedPesewas: 8000,
              tipsPesewas: 0,
            ),
            earnedPesewas: 8000,
            earnedLabel: 'Earned today',
          ),
        ),
      ),
    );

    expect(find.text('Earned today'), findsOneWidget);
    expect(find.text('GH₵ 80.00'), findsOneWidget);
    expect(find.text('GH₵ 0.00'), findsNWidgets(5));
  });

  testWidgets('explains a reversed withdrawal while keeping the funds held', (
    tester,
  ) async {
    final summary = EarningsSummary.fromJson({
      'role': 'driver',
      'period': 'week',
      'availableBalancePesewas': 0,
      'todayAvailableBalancePesewas': 0,
      'weeklyAvailableBalancePesewas': 1500,
      'netEarningsPesewas': 1500,
      'tipsEarnedPesewas': 0,
      'paidOutPesewas': 0,
      'cashCommissionOwedPesewas': 0,
      'pendingPayoutsPesewas': 0,
      'availableBeforeDeductionsPesewas': 0,
      'deductionsAppliedPesewas': 0,
      'withdrawableBalancePesewas': 0,
      'remainingDebtPesewas': 0,
      'heldBalancePesewas': 1500,
      'reconciliationReasonCode': 'WITHDRAWAL_TRANSFER_REVERSED',
      'series': <dynamic>[],
      'granularity': 'day',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EarningsBalanceBreakdownCard(summary: summary)),
      ),
    );

    expect(find.text('GH₵ 15.00'), findsNWidgets(2));
    expect(find.textContaining('transfer was reversed'), findsOneWidget);
    expect(find.textContaining('remain held'), findsOneWidget);
  });
}
