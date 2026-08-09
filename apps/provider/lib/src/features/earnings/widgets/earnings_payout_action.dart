import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

/// Every state rendered in the earnings payout slot.
///
/// Only [payCommission] and [requestPayout] are actions. All other values are
/// status displays, deliberately preventing a stale or older backend response
/// from authorising a money-moving request.
enum EarningsPayoutActionKind {
  payCommission,
  requestPayout,
  automaticPayout,
  payoutInProgress,
  noAvailableBalance,
  payoutUnavailable,
  refreshingBalance,
}

class EarningsPayoutActionState {
  const EarningsPayoutActionState({
    required this.kind,
    required this.label,
    this.commissionOwedPesewas = 0,
  });

  final EarningsPayoutActionKind kind;
  final String label;

  /// Durable full commission debt reported by the backend. Available payout
  /// funds must not be subtracted on-device because they may not be eligible
  /// to offset this debt.
  final int commissionOwedPesewas;

  bool get isActionable =>
      kind == EarningsPayoutActionKind.payCommission ||
      kind == EarningsPayoutActionKind.requestPayout;
}

/// Resolves the earnings CTA from the latest authoritative summary.
///
/// The balance alone is never permission to call the aggregate payout API.
/// The server must explicitly return `manual_aggregate + canRequest=true`.
EarningsPayoutActionState resolveEarningsPayoutAction({
  required EarningsSummary? summary,
  required bool summaryRefreshing,
  required bool summaryHasError,
}) {
  if (summaryRefreshing) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.refreshingBalance,
      label: 'REFRESHING BALANCE',
    );
  }
  if (summary == null || summaryHasError) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.payoutUnavailable,
      label: 'PAYOUT UNAVAILABLE',
    );
  }

  // A transfer already in flight takes precedence over every other state.
  if (summary.pendingPayoutsPesewas > 0 ||
      summary.payoutCapability.reason ==
          PayoutCapabilityReason.payoutInProgress) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.payoutInProgress,
      label: 'PAYOUT IN PROGRESS',
    );
  }

  final commissionOwed = summary.cashCommissionOwedPesewas;
  if (commissionOwed > 0) {
    if (summary.payoutCapability.reason !=
        PayoutCapabilityReason.cashCommissionCoversBalance) {
      return const EarningsPayoutActionState(
        kind: EarningsPayoutActionKind.payoutUnavailable,
        label: 'PAYOUT UNAVAILABLE',
      );
    }
    return EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.payCommission,
      label: 'PAY COMMISSION',
      commissionOwedPesewas: commissionOwed,
    );
  }

  if (summary.availableBalancePesewas <= 0 ||
      summary.payoutCapability.reason ==
          PayoutCapabilityReason.noAvailableBalance) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.noAvailableBalance,
      label: 'NO AVAILABLE BALANCE',
    );
  }

  final capability = summary.payoutCapability;
  if (capability.mode == PayoutCapabilityMode.manualAggregate &&
      capability.canRequest) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.requestPayout,
      label: 'REQUEST PAYOUT',
    );
  }

  if (capability.mode == PayoutCapabilityMode.automaticExact &&
      capability.reason == PayoutCapabilityReason.automaticPayoutActive) {
    return const EarningsPayoutActionState(
      kind: EarningsPayoutActionKind.automaticPayout,
      label: 'AUTOMATIC PAYOUT',
    );
  }

  return const EarningsPayoutActionState(
    kind: EarningsPayoutActionKind.payoutUnavailable,
    label: 'PAYOUT UNAVAILABLE',
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
    required this.onRequestPayout,
  });

  final EarningsSummary? summary;
  final bool summaryRefreshing;
  final bool summaryHasError;
  final ValueChanged<int> onPayCommission;
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
      case EarningsPayoutActionKind.automaticPayout:
      case EarningsPayoutActionKind.payoutInProgress:
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
    final (icon, description) = switch (state.kind) {
      EarningsPayoutActionKind.automaticPayout => (
          Icons.autorenew_rounded,
          'Eligible earnings are sent automatically.',
        ),
      EarningsPayoutActionKind.payoutInProgress => (
          Icons.schedule_rounded,
          'Your settlement is being processed.',
        ),
      EarningsPayoutActionKind.noAvailableBalance => (
          Icons.account_balance_wallet_outlined,
          'There is no eligible balance to pay out.',
        ),
      EarningsPayoutActionKind.refreshingBalance => (
          Icons.sync_rounded,
          'Checking your latest earnings status.',
        ),
      _ => (
          Icons.info_outline_rounded,
          'Payout requests are not available right now.',
        ),
    };

    return Semantics(
      key: const Key('earnings-payout-status'),
      label: '${state.label}. $description',
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
                    description,
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
