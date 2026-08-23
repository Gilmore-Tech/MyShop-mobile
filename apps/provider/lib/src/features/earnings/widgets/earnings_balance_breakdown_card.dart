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
  });

  final EarningsSummary summary;

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
    final headlineLabel = headlineHasDebt ? 'Owings' : 'Available to withdraw';

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
              Icon(
                headlineHasDebt
                    ? Icons.warning_amber_rounded
                    : Icons.account_balance_wallet_outlined,
                size: 17,
                color: headlineHasDebt ? MyShopColors.error : Colors.white70,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headlineLabel,
                  style: MyShopTypography.body2.copyWith(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              headlineHasDebt
                  ? '− ${_formatMoney(remainingDebt)}'
                  : _formatMoney(withdrawable),
              key: const Key('earnings-balance-after-deductions-amount'),
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: headlineHasDebt ? MyShopColors.error : Colors.white,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'How this amount is calculated',
            style: MyShopTypography.caption.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          _BalanceRow(
            label: 'Eligible earnings before debt recovery',
            amountPesewas: availableBefore,
            amountKey: const Key('earnings-before-deductions-amount'),
          ),
          _BalanceRow(
            label: 'Debt recovered from these earnings',
            amountPesewas: deductions,
            amountKey: const Key('earnings-deductions-amount'),
            negative: deductions > 0,
          ),
          _BalanceRow(
            label: 'Available to withdraw',
            amountPesewas: withdrawable,
            amountKey: const Key('earnings-withdrawable-amount'),
          ),
          if (held > 0)
            _BalanceRow(
              label: 'Not yet withdrawable',
              amountPesewas: held,
              amountKey: const Key('earnings-held-amount'),
            ),
          if (remainingDebt > 0)
            _BalanceRow(
              label: 'Still owed to MyShop',
              amountPesewas: remainingDebt,
              amountKey: const Key('earnings-remaining-debt-amount'),
              warning: true,
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

  static String _heldExplanation(
    BuildContext context,
    EarningsSummary summary,
  ) {
    final hasHeldFunds = (summary.heldBalancePesewas ?? 0) > 0;
    if (!hasHeldFunds) {
      return switch (summary.reconciliationReason) {
        EarningsReconciliationReason.withdrawalDestinationReview =>
          'Your withdrawal destination needs review before payouts can continue.',
        EarningsReconciliationReason.withdrawalTransferFailed =>
          'A transfer did not complete and needs review before a safe retry.',
        EarningsReconciliationReason.withdrawalTransferReversed =>
          'A transfer was reversed and is being reconciled.',
        EarningsReconciliationReason.withdrawalFinalizationReview =>
          'The transfer result is recorded, but the withdrawal records still need review.',
        EarningsReconciliationReason.financialReconciliationRequired ||
        EarningsReconciliationReason.unknown =>
          'Your balance needs financial review.',
        EarningsReconciliationReason.none => 'Your balance is being reviewed.',
      };
    }

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
}

/// Keeps historical earnings separate from the balance MyShop can currently
/// send. Net earnings never include tips; any tips shown here are a distinct,
/// directly-paid line.
class EarningsHistoryCard extends StatelessWidget {
  const EarningsHistoryCard({
    super.key,
    required this.label,
    required this.netEarningsPesewas,
    this.secondaryLabel,
    this.secondaryNetEarningsPesewas,
    this.tipsPaidDirectlyPesewas = 0,
    this.tipsLabel = 'Tips paid directly',
  });

  final String label;
  final int netEarningsPesewas;
  final String? secondaryLabel;
  final int? secondaryNetEarningsPesewas;
  final int tipsPaidDirectlyPesewas;
  final String tipsLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('earnings-history-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatMoney(netEarningsPesewas),
            key: const Key('earnings-history-net-amount'),
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            'After MyShop commission',
            style: MyShopTypography.caption.copyWith(
              color: MyShopColors.textSecondary,
            ),
          ),
          if (secondaryLabel != null &&
              secondaryNetEarningsPesewas != null) ...[
            const SizedBox(height: MyShopSpacing.sm),
            _HistoryRow(
              label: secondaryLabel!,
              amountPesewas: secondaryNetEarningsPesewas!,
            ),
          ],
          if (tipsPaidDirectlyPesewas > 0) ...[
            const SizedBox(height: 6),
            _HistoryRow(
              label: tipsLabel,
              amountPesewas: tipsPaidDirectlyPesewas,
              amountKey: const Key('earnings-history-tips-amount'),
            ),
          ],
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'Earnings show what you made. Available to withdraw shows what MyShop can send now.',
            style: MyShopTypography.caption.copyWith(
              color: MyShopColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.label,
    required this.amountPesewas,
    this.amountKey,
  });

  final String label;
  final int amountPesewas;
  final Key? amountKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: MyShopTypography.caption.copyWith(
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              _formatMoney(amountPesewas),
              key: amountKey,
              style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
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
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '$prefix${_formatMoney(amountPesewas)}',
                key: amountKey,
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMoney(int pesewas) => 'GH₵ ${(pesewas / 100).toStringAsFixed(2)}';
