import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

/// Every state rendered in the earnings payout slot.
///
/// Only [payCommission], [withdraw], [setupPayoutMethod], and the legacy
/// [requestPayout] are actions. All other values are
/// status displays, deliberately preventing a stale or older backend response
/// from authorising a money-moving request.
enum EarningsPayoutActionKind {
  payCommission,
  withdraw,
  setupPayoutMethod,
  requestPayout,
  automaticPayout,
  payoutInProgress,
  reconciliationRequired,
  holdActive,
  belowMinimum,
  noAvailableBalance,
  payoutUnavailable,
  refreshingBalance,
}

class EarningsPayoutActionState {
  const EarningsPayoutActionState({
    required this.kind,
    required this.label,
    required this.description,
    this.commissionOwedPesewas = 0,
    this.withdrawablePesewas = 0,
  });

  final EarningsPayoutActionKind kind;
  final String label;
  final String description;

  /// Durable full commission debt reported by the backend. Available payout
  /// funds must not be subtracted on-device because they may not be eligible
  /// to offset this debt.
  final int commissionOwedPesewas;
  final int withdrawablePesewas;

  bool get isActionable =>
      kind == EarningsPayoutActionKind.payCommission ||
      kind == EarningsPayoutActionKind.withdraw ||
      kind == EarningsPayoutActionKind.setupPayoutMethod ||
      kind == EarningsPayoutActionKind.requestPayout;
}

/// Resolves the earnings CTA from the latest authoritative summary.
///
/// The balance alone is never permission to call a payout API. New summaries
/// must return a consistent `request_withdrawal` primary action; old summaries
/// may use the legacy `manual_aggregate + canRequest=true` capability.
EarningsPayoutActionState resolveEarningsPayoutAction({
  required EarningsSummary? summary,
  required bool summaryRefreshing,
  required bool summaryHasError,
}) {
  if (summaryRefreshing) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.refreshingBalance,
      label: 'REFRESHING BALANCE',
      description: 'Checking your latest earnings status.',
    );
  }
  if (summary == null || summaryHasError) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.payoutUnavailable,
      label: 'PAYOUT UNAVAILABLE',
      description: 'Payout requests are not available right now.',
    );
  }

  if (!summary.hasValidCashCommissionOwedPesewas ||
      !summary.hasValidPendingPayoutsPesewas) {
    return _unsupportedPrimaryAction();
  }

  if (summary.hasPrimaryActionContract) {
    return _resolvePrimaryAction(summary);
  }

  if (summary.hasBalanceBreakdownContract) {
    return _unsupportedPrimaryAction();
  }

  // A transfer already in flight takes precedence over every other state.
  if (summary.pendingPayoutsPesewas > 0 ||
      summary.payoutCapability.reason ==
          PayoutCapabilityReason.payoutInProgress) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.payoutInProgress,
      label: 'PAYOUT IN PROGRESS',
      description: 'Your settlement is being processed.',
    );
  }

  final commissionOwed = summary.cashCommissionOwedPesewas;
  if (commissionOwed > 0) {
    if (summary.payoutCapability.reason !=
        PayoutCapabilityReason.cashCommissionCoversBalance) {
      return const EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.payoutUnavailable,
        label: 'PAYOUT UNAVAILABLE',
        description: 'Payout requests are not available right now.',
      );
    }
    return EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.payCommission,
      label: 'PAY COMMISSION',
      description: 'Settle your outstanding cash commission.',
      commissionOwedPesewas: commissionOwed,
    );
  }

  if (summary.availableBalancePesewas <= 0 ||
      summary.payoutCapability.reason ==
          PayoutCapabilityReason.noAvailableBalance) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.noAvailableBalance,
      label: 'NO AVAILABLE BALANCE',
      description: 'There is no eligible balance to pay out.',
    );
  }

  final capability = summary.payoutCapability;
  if (capability.mode == PayoutCapabilityMode.manualAggregate &&
      capability.canRequest) {
    if (summary.availableBalancePesewas <
        EarningsSummary.requiredMinimumWithdrawalPesewas) {
      final moreNeeded = EarningsSummary.requiredMinimumWithdrawalPesewas -
          summary.availableBalancePesewas;
      return EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.belowMinimum,
        label: 'BELOW WITHDRAWAL MINIMUM',
        description: 'GH₵ 15.00 minimum. '
            'GH₵ ${_formatPesewas(moreNeeded)} more must become withdrawable.',
      );
    }
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.requestPayout,
      label: 'REQUEST PAYOUT',
      description: 'Request your available legacy payout balance.',
    );
  }

  if (capability.mode == PayoutCapabilityMode.automaticExact &&
      capability.reason == PayoutCapabilityReason.automaticPayoutActive) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.automaticPayout,
      label: 'AUTOMATIC PAYOUT',
      description: 'Eligible earnings are sent automatically.',
    );
  }

  return const EarningsPayoutActionState(
    kind: EarningsPayoutActionKind.payoutUnavailable,
    label: 'PAYOUT UNAVAILABLE',
    description: 'Payout requests are not available right now.',
  );
}

EarningsPayoutActionState _resolvePrimaryAction(EarningsSummary summary) {
  final action = summary.primaryAction;
  if (action == null ||
      !action.isSupported ||
      !summary.hasAuthoritativeBalanceBreakdown) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.payoutUnavailable,
      label: 'PAYOUT UNAVAILABLE',
      description: 'Refresh the app before trying to move earnings.',
    );
  }

  final remainingDebt = summary.remainingDebtPesewas!;
  final withdrawable = summary.withdrawableBalancePesewas!;

  // Defensive precedence checks mirror the backend contract. A contradictory
  // response is never repaired or reinterpreted on-device.
  if (summary.pendingPayoutsPesewas > 0 &&
      action.kind != EarningsPrimaryActionKind.payoutInProgress &&
      action.kind != EarningsPrimaryActionKind.reconciliationRequired) {
    return _unsupportedPrimaryAction();
  }
  if (remainingDebt > 0 &&
      action.kind != EarningsPrimaryActionKind.payRemainingCommission &&
      action.kind != EarningsPrimaryActionKind.payoutInProgress &&
      action.kind != EarningsPrimaryActionKind.reconciliationRequired) {
    return _unsupportedPrimaryAction();
  }

  switch (action.kind) {
    case EarningsPrimaryActionKind.reconciliationRequired:
      if (action.reasonCode !=
          EarningsPrimaryActionReasonCodes.reconciliationRequired) {
        return _unsupportedPrimaryAction();
      }
      return const EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.reconciliationRequired,
        label: 'REVIEW REQUIRED',
        description: 'Your balance needs reconciliation before another payout.',
      );
    case EarningsPrimaryActionKind.payoutInProgress:
      if (action.reasonCode !=
          EarningsPrimaryActionReasonCodes.payoutInProgress) {
        return _unsupportedPrimaryAction();
      }
      return const EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.payoutInProgress,
        label: 'PAYOUT IN PROGRESS',
        description: 'Your settlement is being processed.',
      );
    case EarningsPrimaryActionKind.payRemainingCommission:
      if (action.reasonCode !=
              EarningsPrimaryActionReasonCodes.outstandingDeductions ||
          action.amountPesewas <= 0 ||
          action.amountPesewas != remainingDebt ||
          summary.cashCommissionOwedPesewas != remainingDebt) {
        return _unsupportedPrimaryAction();
      }
      return EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.payCommission,
        label: 'PAY COMMISSION',
        description: 'Settle the remaining commission owed to MyShop.',
        commissionOwedPesewas: action.amountPesewas,
      );
    case EarningsPrimaryActionKind.setupPayoutMethod:
      if (action.reasonCode !=
          EarningsPrimaryActionReasonCodes.payoutDestinationRequired) {
        return _unsupportedPrimaryAction();
      }
      return const EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.setupPayoutMethod,
        label: 'SET UP PAYOUT METHOD',
        description: 'Verify where MyShop should send your withdrawals.',
      );
    case EarningsPrimaryActionKind.requestWithdrawal:
      if (action.reasonCode !=
              EarningsPrimaryActionReasonCodes.manualWithdrawalAvailable ||
          action.amountPesewas <= 0 ||
          action.amountPesewas != withdrawable ||
          summary.cashCommissionOwedPesewas != 0 ||
          summary.minimumWithdrawalPesewas !=
              EarningsSummary.requiredMinimumWithdrawalPesewas ||
          withdrawable < EarningsSummary.requiredMinimumWithdrawalPesewas) {
        return _unsupportedPrimaryAction();
      }
      return EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.withdraw,
        label: 'WITHDRAW',
        description: 'Withdraw your current server-confirmed balance.',
        withdrawablePesewas: action.amountPesewas,
      );
    case EarningsPrimaryActionKind.none:
      if (action.amountPesewas != 0) return _unsupportedPrimaryAction();
      return switch (action.reasonCode) {
        EarningsPrimaryActionReasonCodes.holdActive =>
          const EarningsPayoutActionState(
            kind: EarningsPayoutActionKind.holdActive,
            label: 'EARNINGS ON HOLD',
            description:
                'Some held earnings will become eligible after the time shown above.',
          ),
        EarningsPrimaryActionReasonCodes.belowMinimum =>
          _belowMinimumAction(summary, withdrawable),
        EarningsPrimaryActionReasonCodes.noWithdrawableBalance =>
          const EarningsPayoutActionState(
            kind: EarningsPayoutActionKind.noAvailableBalance,
            label: 'NO WITHDRAWABLE BALANCE',
            description: 'There is no balance available to withdraw.',
          ),
        EarningsPrimaryActionReasonCodes.automaticPayoutActive =>
          const EarningsPayoutActionState(
            kind: EarningsPayoutActionKind.automaticPayout,
            label: 'AUTOMATIC PAYOUT ACTIVE',
            description: 'Eligible earnings are sent automatically.',
          ),
        _ => _unsupportedPrimaryAction(),
      };
    case EarningsPrimaryActionKind.unsupported:
      return _unsupportedPrimaryAction();
  }
}

EarningsPayoutActionState _belowMinimumAction(
  EarningsSummary summary,
  int withdrawable,
) {
  const minimum = EarningsSummary.requiredMinimumWithdrawalPesewas;
  if (summary.minimumWithdrawalPesewas != minimum || withdrawable >= minimum) {
    return _unsupportedPrimaryAction();
  }
  final moreNeeded = minimum - withdrawable;
  return EarningsPayoutActionState(
    kind: EarningsPayoutActionKind.belowMinimum,
    label: 'BELOW WITHDRAWAL MINIMUM',
    description: 'GH₵ ${_formatPesewas(minimum)} minimum. '
        'GH₵ ${_formatPesewas(moreNeeded)} more must become withdrawable.',
  );
}

String _formatPesewas(int pesewas) => (pesewas / 100).toStringAsFixed(2);

EarningsPayoutActionState _unsupportedPrimaryAction() {
  return const EarningsPayoutActionState(
    kind: EarningsPayoutActionKind.payoutUnavailable,
    label: 'PAYOUT UNAVAILABLE',
    description: 'Refresh the app before trying to move earnings.',
  );
}

/// Shared Driver/Artisan payout slot. Money-moving states render as buttons;
/// automatic, unavailable and transitional states render as non-interactive
/// status panels so they cannot be mistaken for disabled actions.
class EarningsPayoutAction extends StatelessWidget {
  const EarningsPayoutAction({
    super.key,
    required this.summary,
    required this.summaryRefreshing,
    required this.summaryHasError,
    required this.onPayCommission,
    required this.onWithdraw,
    required this.onSetupPayoutMethod,
    required this.onRequestPayout,
  });

  final EarningsSummary? summary;
  final bool summaryRefreshing;
  final bool summaryHasError;
  final ValueChanged<int> onPayCommission;
  final ValueChanged<int> onWithdraw;
  final VoidCallback onSetupPayoutMethod;
  final VoidCallback onRequestPayout;

  @override
  Widget build(BuildContext context) {
    final state = resolveEarningsPayoutAction(
      summary: summary,
      summaryRefreshing: summaryRefreshing,
      summaryHasError: summaryHasError,
    );

    switch (state.kind) {
      case EarningsPayoutActionKind.payCommission:
        return ElevatedButton.icon(
          key: const Key('earnings-pay-commission'),
          onPressed: () => onPayCommission(state.commissionOwedPesewas),
          icon: const Icon(Icons.payments_rounded, size: 18),
          label: Text(state.label),
          style: _buttonStyle(
            backgroundColor: MyShopColors.error,
            foregroundColor: Colors.white,
          ),
        );
      case EarningsPayoutActionKind.requestPayout:
        return ElevatedButton.icon(
          key: const Key('earnings-request-payout'),
          onPressed: onRequestPayout,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Text(state.label),
          style: _buttonStyle(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
          ),
        );
      case EarningsPayoutActionKind.withdraw:
        return ElevatedButton.icon(
          key: const Key('earnings-withdraw'),
          onPressed: () => onWithdraw(state.withdrawablePesewas),
          icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
          label: Text(state.label),
          style: _buttonStyle(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
          ),
        );
      case EarningsPayoutActionKind.setupPayoutMethod:
        return ElevatedButton.icon(
          key: const Key('earnings-setup-payout-method'),
          onPressed: onSetupPayoutMethod,
          icon: const Icon(Icons.verified_user_outlined, size: 18),
          label: Text(state.label),
          style: _buttonStyle(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
          ),
        );
      case EarningsPayoutActionKind.automaticPayout:
      case EarningsPayoutActionKind.payoutInProgress:
      case EarningsPayoutActionKind.reconciliationRequired:
      case EarningsPayoutActionKind.holdActive:
      case EarningsPayoutActionKind.belowMinimum:
      case EarningsPayoutActionKind.noAvailableBalance:
      case EarningsPayoutActionKind.payoutUnavailable:
      case EarningsPayoutActionKind.refreshingBalance:
        return _PayoutStatus(state: state);
    }
  }

  static ButtonStyle _buttonStyle({
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: const Size(double.infinity, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      textStyle: const TextStyle(
        fontFamily: 'Raleway',
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _PayoutStatus extends StatelessWidget {
  const _PayoutStatus({required this.state});

  final EarningsPayoutActionState state;

  @override
  Widget build(BuildContext context) {
    final icon = switch (state.kind) {
      EarningsPayoutActionKind.automaticPayout => Icons.autorenew_rounded,
      EarningsPayoutActionKind.payoutInProgress => Icons.schedule_rounded,
      EarningsPayoutActionKind.reconciliationRequired =>
        Icons.report_problem_outlined,
      EarningsPayoutActionKind.holdActive => Icons.lock_clock_outlined,
      EarningsPayoutActionKind.belowMinimum => Icons.savings_outlined,
      EarningsPayoutActionKind.noAvailableBalance =>
        Icons.account_balance_wallet_outlined,
      EarningsPayoutActionKind.refreshingBalance => Icons.sync_rounded,
      _ => Icons.info_outline_rounded,
    };

    return Semantics(
      key: const Key('earnings-payout-status'),
      label: '${state.label}. ${state.description}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: MyShopColors.textSecondary),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.label,
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  Text(
                    state.description,
                    style: MyShopTypography.caption.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
