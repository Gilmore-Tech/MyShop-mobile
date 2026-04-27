import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../artisan_home/providers/artisan_earnings_provider.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../driver_home/data/earnings_service.dart';
import '../data/ratings_service.dart';
import '../providers/ratings_provider.dart';
import '../widgets/commission_card.dart';
import '../widgets/payout_request_flow.dart';
import '../widgets/payouts_list.dart';
import '../widgets/weekly_performance_card.dart';

/// Artisan-side earnings details screen.
///
/// PRD Reference: PRD 5.4 — provider earnings & payouts.
/// Fetches real earnings from GET /payments/earnings?period=today|week|month.
class ArtisanEarningsScreen extends ConsumerStatefulWidget {
  const ArtisanEarningsScreen({super.key});

  @override
  ConsumerState<ArtisanEarningsScreen> createState() =>
      _ArtisanEarningsScreenState();
}

class _ArtisanEarningsScreenState
    extends ConsumerState<ArtisanEarningsScreen> {
  _Period _period = _Period.weekly;

  String get _periodKey {
    switch (_period) {
      case _Period.today:
        return 'today';
      case _Period.weekly:
        return 'week';
      case _Period.monthly:
        return 'month';
    }
  }

  @override
  Widget build(BuildContext context) {
    final earningsAsync =
        ref.watch(artisanEarningsByPeriodProvider(_periodKey));
    final user = ref.watch(currentUserProvider);
    final ap = user?.artisanProfile;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: earningsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: MyShopColors.primaryGold,
                  ),
                ),
                error: (_, __) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: MyShopColors.textSecondary,
                      ),
                      const SizedBox(height: MyShopSpacing.sm),
                      Text(
                        'Could not load earnings',
                        style: MyShopTypography.body1,
                      ),
                      const SizedBox(height: MyShopSpacing.sm),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          artisanEarningsByPeriodProvider(_periodKey),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (earnings) => _EarningsContent(
                  earnings: earnings,
                  period: _period,
                  onPeriodChanged: (p) => setState(() => _period = p),
                  jobsDone: ap?.completedJobsCount ?? 0,
                ),
              ),
            ),
            const _PayoutFooter(),
          ],
        ),
      ),
    );
  }
}

class _EarningsContent extends ConsumerWidget {
  const _EarningsContent({
    required this.earnings,
    required this.period,
    required this.onPeriodChanged,
    required this.jobsDone,
  });

  final DriverEarnings earnings;
  final _Period period;
  final ValueChanged<_Period> onPeriodChanged;
  final int jobsDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The "Available" headline now reflects the backend's authoritative
    // withdrawable balance (escrow-released, not yet paid out) — which is
    // what the payout endpoint actually accepts. The period total stays
    // alongside as gross revenue context for the selected window.
    final totalPesewas = period == _Period.today
        ? earnings.todayAmountPesewas
        : earnings.weekAmountPesewas;
    final totalGhs = totalPesewas / 100;
    // Platform commission is 20% of total
    final commissionGhs = totalGhs * 0.20;
    final availableGhs = earnings.availableBalancePesewas / 100;

    // Weekly chart and commission breakdown always show this-week data
    // regardless of the segmented control above (which drives the balance
    // card). Riverpod caches by family key so this is at most one extra
    // network call when the user is viewing a non-week period.
    final weekAsync = ref.watch(artisanEarningsByPeriodProvider('week'));
    final week = weekAsync.valueOrNull ?? DriverEarnings.empty;

    final ratings =
        ref.watch(providerRatingsProvider).valueOrNull ??
            ProviderRatingsSummary.empty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      children: [
        _PeriodSegmented(value: period, onChanged: onPeriodChanged),
        const SizedBox(height: MyShopSpacing.md),
        _BalanceCard(
          available: availableGhs,
          totalRevenue: totalGhs,
          jobsDone: jobsDone,
          ratings: ratings,
        ),
        const SizedBox(height: MyShopSpacing.md),
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                label: 'JOBS',
                value: earnings.todayTrips.toString(),
                subtitle: 'Today',
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: _MiniStatCard(
                label: 'PLATFORM FEE',
                value: 'GH₵ ${commissionGhs.toStringAsFixed(2)}',
                subtitle: '20% commission',
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Weekly performance chart (same widget the driver uses)
        WeeklyPerformanceCard(
          peakHours: week.peakHours,
          emptyLabel: 'No jobs yet this week',
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Commission & Tax breakdown (weekly)
        CommissionCard(
          weekPesewas: week.weekAmountPesewas,
          weekCommissionPesewas: week.weekCommissionPesewas,
          weekNetPesewas: week.weekNetPesewas,
        ),
        const SizedBox(height: MyShopSpacing.lg),

        // Recent Payouts header + list (backend filters by role)
        Row(
          children: [
            const Icon(Icons.history,
                size: 18, color: MyShopColors.textPrimary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Recent Payouts',
                style: MyShopTypography.h2.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.sm),
        const PayoutsList(),
        const SizedBox(height: MyShopSpacing.lg),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Text(
        'Earnings Details',
        style: MyShopTypography.h1.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period segmented control
// ---------------------------------------------------------------------------

enum _Period { today, weekly, monthly }

class _PeriodSegmented extends StatelessWidget {
  const _PeriodSegmented({required this.value, required this.onChanged});

  final _Period value;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          _seg('Today', _Period.today),
          _seg('Weekly', _Period.weekly),
          _seg('Monthly', _Period.monthly),
        ],
      ),
    );
  }

  Widget _seg(String label, _Period p) {
    final selected = value == p;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(p),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? MyShopColors.surfaceWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: MyShopTypography.body1.copyWith(
              color: selected
                  ? MyShopColors.textPrimary
                  : MyShopColors.textSecondary,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balance card
// ---------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.available,
    required this.totalRevenue,
    required this.jobsDone,
    required this.ratings,
  });

  final double available;
  final double totalRevenue;
  final int jobsDone;
  final ProviderRatingsSummary ratings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.lg),
      decoration: BoxDecoration(
        color: MyShopColors.darkSlate,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Net Earnings',
                  style: MyShopTypography.body1.copyWith(
                    color:
                        MyShopColors.textOnDarkSlate.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (ratings.hasRatings) _RatingChip(ratings: ratings),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'GH₵ ${available.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textOnDarkSlate,
              height: 1.1,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  label: 'GROSS REVENUE',
                  value: 'GH₵ ${totalRevenue.toStringAsFixed(2)}',
                ),
              ),
              Expanded(
                child: _miniStat(
                  label: 'JOBS DONE',
                  value: jobsDone.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.primaryGold,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MyShopColors.textOnDarkSlate,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rating chip (header of the balance card)
// ---------------------------------------------------------------------------

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.ratings});

  final ProviderRatingsSummary ratings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            size: 14,
            color: MyShopColors.primaryGold,
          ),
          const SizedBox(width: 4),
          Text(
            ratings.averageDisplay,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textOnDarkSlate,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '(${ratings.count})',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textOnDarkSlate.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini stat card
// ---------------------------------------------------------------------------

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: MyShopTypography.h2.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.primaryGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payout footer
// ---------------------------------------------------------------------------

class _PayoutFooter extends ConsumerStatefulWidget {
  const _PayoutFooter();

  @override
  ConsumerState<_PayoutFooter> createState() => _PayoutFooterState();
}

class _PayoutFooterState extends ConsumerState<_PayoutFooter> {
  bool _isRequesting = false;

  Future<void> _onTap() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      await requestProviderPayout(context, ref);
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pre-flight balance gate driven by the backend's authoritative
    // `availableBalancePesewas` — the same number the payout endpoint
    // checks server-side, so the gate matches the eventual response.
    final weekAsync = ref.watch(artisanEarningsByPeriodProvider('week'));
    final available =
        weekAsync.whenOrNull(data: (e) => e.availableBalancePesewas) ?? 0;
    final belowThreshold = available < kMinPayoutPesewas;
    final canRequest = !_isRequesting && !belowThreshold;

    final hint = belowThreshold
        ? 'Earn at least GHS ${(kMinPayoutPesewas / 100).toStringAsFixed(0)} to request a payout'
        : 'Settlement usually takes 2-4 hours';

    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md + MediaQuery.of(context).padding.bottom * 0.2,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hint,
                  style: MyShopTypography.body2,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          GestureDetector(
            onTap: canRequest ? _onTap : null,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: canRequest
                    ? MyShopColors.darkSlate
                    : MyShopColors.darkSlate.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(28),
              ),
              alignment: Alignment.center,
              child: _isRequesting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            MyShopColors.textOnDarkSlate),
                      ),
                    )
                  : Text(
                      'Request Payout Now',
                      style: MyShopTypography.button.copyWith(
                        color: MyShopColors.textOnDarkSlate,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
