import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

/// Renders the additive, server-authored provider balance contract without
/// reconstructing payout arithmetic on-device.
///
/// Callers should use this only when
/// [EarningsSummary.hasAuthoritativeBalanceBreakdown] is true. Older backend
/// summaries continue through the legacy cards on their respective screens.
class EarningsBalanceBreakdownCard extends StatelessWidget {
  const EarningsBalanceBreakdownCard({
    super.key,
    required this.summary,
    this.earnedPesewas,
    this.earnedLabel,
  });

  final EarningsSummary summary;
  final int? earnedPesewas;
  final String? earnedLabel;

  @override
  Widget build(BuildContext context) {
    if (!summary.hasAuthoritativeBalanceBreakdown) {
      return const SizedBox.shrink();
    }

    final availableBefore = summary.availableBeforeDeductionsPesewas!;
    final deductions = summary.deductionsAppliedPesewas!;
    final withdrawable = summary.withdrawableBalancePesewas!;
    final remainingDebt = summary.remainingDebtPesewas!;
    final held = summary.heldBalancePesewas!;
    final headlineHasDebt = remainingDebt > 0;

    return Container(
      key: const Key('earnings-authoritative-balance-card'),
      padding: const EdgeInsets.all(MyShopSpacing.lg),
      decoration: BoxDecoration(
        color: MyShopColors.darkSlate,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 17,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                'Balance after deductions',
                style: MyShopTypography.body2.copyWith(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Server balance',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            headlineHasDebt
                ? '− ${_money(remainingDebt)}'
                : _money(withdrawable),
            key: const Key('earnings-balance-after-deductions-amount'),
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: headlineHasDebt ? MyShopColors.error : Colors.white,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: MyShopSpacing.sm),
          _BalanceRow(
            label: earnedLabel ?? _earnedLabel(summary.period),
            amountPesewas: earnedPesewas ?? summary.selectedPeriodEarnedPesewas,
            amountKey: const Key('earnings-earned-amount'),
          ),
          _BalanceRow(
            label: 'Available before deductions',
            amountPesewas: availableBefore,
            amountKey: const Key('earnings-before-deductions-amount'),
          ),
          _BalanceRow(
            label: 'Deductions applied',
            amountPesewas: deductions,
            amountKey: const Key('earnings-deductions-amount'),
            negative: deductions > 0,
          ),
          _BalanceRow(
            label: 'Held',
            amountPesewas: held,
            amountKey: const Key('earnings-held-amount'),
          ),
          _BalanceRow(
            label: 'Remaining debt',
            amountPesewas: remainingDebt,
            amountKey: const Key('earnings-remaining-debt-amount'),
            warning: remainingDebt > 0,
          ),
          if (held > 0 ||
              summary.reconciliationReason !=
                  EarningsReconciliationReason.none) ...[
            const SizedBox(height: MyShopSpacing.sm),
            Container(
              key: const Key('earnings-hold-explanation'),
              width: double.infinity,
              padding: const EdgeInsets.all(MyShopSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _heldExplanation(context, summary),
                style: MyShopTypography.caption.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _earnedLabel(EarningsPeriod period) => switch (period) {
        EarningsPeriod.today => 'Earned today',
        EarningsPeriod.week => 'Earned this week',
        EarningsPeriod.month => 'Earned this month',
      };

  static String _heldExplanation(
    BuildContext context,
    EarningsSummary summary,
  ) {
    final reviewCopy = switch (summary.reconciliationReason) {
      EarningsReconciliationReason.withdrawalDestinationReview =>
        'These funds are held because the verified MoMo destination changed or needs review.',
      EarningsReconciliationReason.withdrawalTransferFailed =>
        'The transfer did not complete. These funds remain held while MyShop verifies a safe retry.',
      EarningsReconciliationReason.withdrawalTransferReversed =>
        'The transfer was reversed. These funds remain held while MyShop reconciles it.',
      EarningsReconciliationReason.withdrawalFinalizationReview =>
        'The transfer result is recorded, but the withdrawal records still need review.',
      EarningsReconciliationReason.financialReconciliationRequired ||
      EarningsReconciliationReason.unknown =>
        'These funds are held while MyShop reconciles your financial records.',
      EarningsReconciliationReason.none => null,
    };
    if (reviewCopy != null) return reviewCopy;

    final eligibleAt = summary.nextPayoutEligibleAt;
    if (eligibleAt == null) {
      return 'Some earnings are currently held and are not withdrawable yet.';
    }
    final local = eligibleAt.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return 'The next held earnings become eligible after $date at $time.';
  }

  static String _money(int pesewas) =>
      'GH₵ ${(pesewas / 100).toStringAsFixed(2)}';
}

/// Fail-closed replacement for a malformed or partially rolled-out additive
/// balance response. It deliberately hides every amount from that response so
/// stale legacy arithmetic cannot look authoritative.
class EarningsBalanceUnavailableCard extends StatelessWidget {
  const EarningsBalanceUnavailableCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('earnings-balance-unavailable-card'),
      padding: const EdgeInsets.all(MyShopSpacing.lg),
      decoration: BoxDecoration(
        color: MyShopColors.darkSlate,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sync_problem_outlined,
            color: Colors.white70,
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'Balance temporarily unavailable',
            style: MyShopTypography.h3.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Refresh earnings to see your available balance, deductions, '
            'held funds and remaining debt.',
            style: MyShopTypography.body2.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.amountPesewas,
    required this.amountKey,
    this.negative = false,
    this.warning = false,
  });

  final String label;
  final int amountPesewas;
  final Key amountKey;
  final bool negative;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? MyShopColors.error : Colors.white;
    final prefix = negative ? '− ' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: MyShopTypography.caption.copyWith(color: Colors.white70),
            ),
          ),
          Text(
            '$prefix${EarningsBalanceBreakdownCard._money(amountPesewas)}',
            key: amountKey,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
