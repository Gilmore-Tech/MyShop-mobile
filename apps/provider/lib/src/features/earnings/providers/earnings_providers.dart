import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../profile/providers/provider_type_provider.dart';
import '../data/earnings_service.dart';

/// Provides [EarningsService] backed by the app's Dio client.
final earningsServiceProvider = Provider<EarningsService>((ref) {
  return EarningsService(ref.watch(dioProvider));
});

/// Maps the active [providerTypeProvider] state to the API role string.
/// Always pass this to earnings calls so a future second profile doesn't
/// leak earnings across roles (per backend handoff §2).
final activeEarningsRoleProvider = Provider<EarningsRole>((ref) {
  final type = ref.watch(providerTypeProvider);
  return type.isDriver ? EarningsRole.driver : EarningsRole.artisan;
});

// ────────────────────────────────────────────────────────────────────────────
// Today-card — homepage
// ────────────────────────────────────────────────────────────────────────────

/// Driver/artisan homepage "Today's earnings" card.
///
/// Family key is the role so a dual-role test account doesn't pin one
/// flavour's data after the role-picker switches.
///
/// Re-throws on failure so callers can render an error banner with retry —
/// silently returning empty would let an API outage look identical to "no
/// earnings yet" (the failure mode that hid a recent prod regression).
final todayCardProvider =
    FutureProvider.family<EarningsTodayCard, EarningsRole>((ref, role) async {
  return ref.watch(earningsServiceProvider).getTodayCard(role: role);
});

/// Convenience wrapper that auto-resolves the active role from
/// [activeEarningsRoleProvider]. Use this from screens that should always
/// reflect "the currently-active provider scope".
final activeTodayCardProvider = FutureProvider<EarningsTodayCard>((ref) async {
  final role = ref.watch(activeEarningsRoleProvider);
  return ref.watch(todayCardProvider(role).future);
});

// ────────────────────────────────────────────────────────────────────────────
// Summary — earnings tab top card
// ────────────────────────────────────────────────────────────────────────────

/// Family key for [earningsSummaryProvider]. Carries both the role and the
/// selected period — Riverpod treats two equal keys as the same provider so
/// the period switcher only re-fetches once per (role, period) pair.
class EarningsSummaryKey {
  const EarningsSummaryKey({required this.role, required this.period});

  final EarningsRole role;
  final EarningsPeriod period;

  @override
  bool operator ==(Object other) =>
      other is EarningsSummaryKey &&
      other.role == role &&
      other.period == period;

  @override
  int get hashCode => Object.hash(role, period);
}

/// Earnings tab top card — available balance + sparkline + selected-period
/// net. Server-cached for 5 minutes, invalidated on payment status flips.
final earningsSummaryProvider =
    FutureProvider.family<EarningsSummary, EarningsSummaryKey>(
        (ref, key) async {
  return ref
      .watch(earningsServiceProvider)
      .getSummary(role: key.role, period: key.period);
});

// ────────────────────────────────────────────────────────────────────────────
// Report — detailed report view
// ────────────────────────────────────────────────────────────────────────────

/// Detailed report — gross/net/commission/tips/avg-fare + full graph.
/// Family-keyed by [EarningsReportQuery] so preset-mode and custom-range
/// queries cache independently.
///
/// Custom-range responses are not cached server-side — debounce date-picker
/// changes by ~300ms before invalidating this provider.
final earningsReportProvider =
    FutureProvider.family<EarningsReport, EarningsReportQuery>(
        (ref, query) async {
  return ref.watch(earningsServiceProvider).getReport(query);
});

// ────────────────────────────────────────────────────────────────────────────
// Payouts (role-agnostic for now — backend ticket pending for dual-role)
// ────────────────────────────────────────────────────────────────────────────

/// Recent payouts (most-recent-first, capped at 50). Refreshed on ride
/// completion (socket listener invalidates) and on payout-request success.
final payoutsProvider = FutureProvider<List<DriverPayout>>((ref) async {
  return ref.watch(earningsServiceProvider).getPayouts();
});

/// One authoritative cache-bust entry point for settlement notifications.
///
/// A Paystack transfer can change the provider's withdrawable balance without
/// changing the historical TODAY/WEEKLY earnings totals. Invalidate every
/// server-backed earnings surface together so the balance, pending-settlement
/// amount and payout history cannot disagree after a foreground push or a
/// notification tap.
const earningsSettlementRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 3),
  Duration(seconds: 8),
];

final earningsSettlementRetryDelaysProvider = Provider<List<Duration>>(
  (_) => earningsSettlementRetryDelays,
);

/// Bounded, event-driven protection against completion-before-ledger races.
///
/// This is intentionally not a global poller. It runs only after a local or
/// server settlement signal, cancels duplicate waves, and performs three
/// finite retries. A post-commit `earnings:updated`/`earnings_updated` event
/// uses the same path so every visible earnings surface converges together.
class EarningsRefreshCoordinator {
  EarningsRefreshCoordinator(
    this._ref, {
    this.retryDelays = earningsSettlementRetryDelays,
  });

  final Ref _ref;
  final List<Duration> retryDelays;
  final List<Timer> _timers = <Timer>[];
  bool _disposed = false;

  int get pendingRetryCount => _timers.where((timer) => timer.isActive).length;

  void invalidateNow() {
    if (_disposed) return;
    _ref.invalidate(todayCardProvider);
    _ref.invalidate(earningsSummaryProvider);
    _ref.invalidate(earningsReportProvider);
    _ref.invalidate(payoutsProvider);
  }

  void scheduleAfterSettlement() {
    if (_disposed) return;
    _cancelTimers();
    invalidateNow();
    for (final delay in retryDelays) {
      _timers.add(Timer(delay, invalidateNow));
    }
  }

  void dispose() {
    _disposed = true;
    _cancelTimers();
  }

  void _cancelTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}

final earningsRefreshCoordinatorProvider = Provider<EarningsRefreshCoordinator>(
  (ref) {
    final coordinator = EarningsRefreshCoordinator(
      ref,
      retryDelays: ref.watch(earningsSettlementRetryDelaysProvider),
    );
    ref.onDispose(coordinator.dispose);
    return coordinator;
  },
);

final invalidateEarningsCachesProvider = Provider<void Function()>((ref) {
  return ref.watch(earningsRefreshCoordinatorProvider).invalidateNow;
});

final refreshEarningsAfterSettlementProvider = Provider<void Function()>((ref) {
  return ref.watch(earningsRefreshCoordinatorProvider).scheduleAfterSettlement;
});

/// The payout CTA must never act on a previous summary while Riverpod is
/// fetching the post-settlement balance. TODAY/WEEKLY values remain visible;
/// only the money-moving action is fenced until the authoritative summary is
/// current again.
bool canRequestPayoutFromSummary({
  required EarningsSummary? summary,
  required bool summaryRefreshing,
  required bool summaryHasError,
}) {
  if (summary == null || summaryRefreshing || summaryHasError) return false;
  if (!summary.hasValidCashCommissionOwedPesewas ||
      !summary.hasValidPendingPayoutsPesewas) {
    return false;
  }
  if (summary.hasPrimaryActionContract) {
    final action = summary.primaryAction;
    return summary.hasAuthoritativeBalanceBreakdown &&
        action?.kind == EarningsPrimaryActionKind.requestWithdrawal &&
        action?.reasonCode ==
            EarningsPrimaryActionReasonCodes.manualWithdrawalAvailable &&
        action!.amountPesewas > 0 &&
        action.amountPesewas == summary.withdrawableBalancePesewas &&
        summary.minimumWithdrawalPesewas ==
            EarningsSummary.requiredMinimumWithdrawalPesewas &&
        action.amountPesewas >=
            EarningsSummary.requiredMinimumWithdrawalPesewas &&
        summary.cashCommissionOwedPesewas == 0 &&
        summary.remainingDebtPesewas == 0 &&
        summary.pendingPayoutsPesewas == 0;
  }
  if (summary.hasBalanceBreakdownContract) return false;
  return summary.payoutCapability.mode ==
          PayoutCapabilityMode.manualAggregate &&
      summary.payoutCapability.canRequest &&
      summary.cashCommissionOwedPesewas == 0 &&
      summary.availableBalancePesewas >=
          EarningsSummary.requiredMinimumWithdrawalPesewas &&
      summary.pendingPayoutsPesewas == 0;
}
