import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../data/earnings_service.dart';
import '../data/ratings_service.dart';
import '../providers/earnings_providers.dart';
import '../providers/ratings_provider.dart';
import '../widgets/commission_card.dart';
import '../widgets/payout_request_flow.dart';
import '../widgets/payouts_list.dart';
import '../widgets/weekly_performance_card.dart';

/// Artisan-side earnings details screen.
///
/// PRD Reference: PRD 5.4 — provider earnings & payouts.
///
/// Wires the new earnings split:
///   - summary (selected period) → top balance card + sparkline + period-net
///   - report  (week)            → commission card + average fare context
const _kArtisanRole = EarningsRole.artisan;

class ArtisanEarningsScreen extends ConsumerStatefulWidget {
  const ArtisanEarningsScreen({super.key});

  @override
  ConsumerState<ArtisanEarningsScreen> createState() =>
      _ArtisanEarningsScreenState();
}

class _ArtisanEarningsScreenState
    extends ConsumerState<ArtisanEarningsScreen> {
  EarningsPeriod _period = EarningsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final summaryKey =
        EarningsSummaryKey(role: _kArtisanRole, period: _period);
    final summaryAsync = ref.watch(earningsSummaryProvider(summaryKey));

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: summaryAsync.when(
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
                          earningsSummaryProvider(summaryKey),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (summary) => _EarningsContent(
                  summary: summary,
                  period: _period,
                  onPeriodChanged: (p) => setState(() => _period = p),
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
    required this.summary,
    required this.period,
    required this.onPeriodChanged,
  });

  final EarningsSummary summary;
  final EarningsPeriod period;
  final ValueChanged<EarningsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Top headline reflects the backend's authoritative withdrawable balance
    // — what the payout endpoint will actually accept. The selected-period
    // net earnings + a weekly commission card live below it.
    final user = ref.watch(currentUserProvider);
    final jobsDone = user?.artisanProfile?.completedJobsCount ?? 0;
    final available = summary.availableBalancePesewas / 100;
    final periodNet = summary.netEarningsPesewas / 100;

    // Commission breakdown always uses the week regardless of the period
    // toggle above (which drives the headline). Riverpod caches by family
    // key so this is one extra request only when the user switches off the
    // week.
    final weekReportQuery = const EarningsReportQuery.preset(
      role: _kArtisanRole,
      period: EarningsPeriod.week,
    );
    final weekReportAsync = ref.watch(earningsReportProvider(weekReportQuery));
    final weekReport = weekReportAsync.valueOrNull;

    final ratings = ref.watch(providerRatingsProvider).valueOrNull ??
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
          available: available,
          periodNet: periodNet,
          jobsDone: jobsDone,
          ratings: ratings,
        ),
        const SizedBox(height: MyShopSpacing.md),
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                label: 'JOBS THIS WEEK',
                value: '${weekReport?.bookingsCompleted ?? 0}',
                subtitle: 'Completed',
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: _MiniStatCard(
                label: 'AVG FARE',
                value:
                    'GH₵ ${((weekReport?.averageFarePesewas ?? 0) / 100).toStringAsFixed(2)}',
                subtitle: 'Per job',
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Performance chart from the summary's gap-filled series
        WeeklyPerformanceCard(
          series: summary.series,
          granularity: summary.granularity,
          subtitle: _seriesSubtitle(period),
          emptyLabel: 'No jobs yet this period',
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Commission & Tax (week)
        CommissionCard(
          grossPesewas: weekReport?.grossEarningsPesewas ?? 0,
          commissionPesewas: weekReport?.commissionChargedPesewas ?? 0,
          netPesewas: weekReport?.netEarningsPesewas ?? 0,
        ),
        const SizedBox(height: MyShopSpacing.lg),

        // Recent Payouts
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

  static String _seriesSubtitle(EarningsPeriod p) {
    switch (p) {
      case EarningsPeriod.today:
        return 'Net earnings today';
      case EarningsPeriod.week:
        return 'Net earnings, last 7 days';
      case EarningsPeriod.month:
        return 'Net earnings, last 30 days';
    }
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

class _PeriodSegmented extends StatelessWidget {
  const _PeriodSegmented({required this.value, required this.onChanged});

  final EarningsPeriod value;
  final ValueChanged<EarningsPeriod> onChanged;

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
          _seg('Today', EarningsPeriod.today),
          _seg('Weekly', EarningsPeriod.week),
          _seg('Monthly', EarningsPeriod.month),
        ],
      ),
    );
  }

  Widget _seg(String label, EarningsPeriod p) {
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
    required this.periodNet,
    required this.jobsDone,
    required this.ratings,
  });

  final double available;
  final double periodNet;
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
                  'Available Balance',
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
                  label: 'PERIOD NET',
                  value: 'GH₵ ${periodNet.toStringAsFixed(2)}',
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
    // `availableBalancePesewas` — same number the payout endpoint checks
    // server-side. We read it from the week summary because that's the
    // default tab; switching periods doesn't move the available balance
    // (it's period-agnostic per the backend contract).
    const summaryKey = EarningsSummaryKey(
      role: _kArtisanRole,
      period: EarningsPeriod.week,
    );
    final summaryAsync = ref.watch(earningsSummaryProvider(summaryKey));
    final available =
        summaryAsync.whenOrNull(data: (s) => s.availableBalancePesewas) ?? 0;
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
