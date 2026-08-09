import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../data/ratings_service.dart';
import '../providers/earnings_providers.dart';
import '../providers/ratings_provider.dart';
import '../widgets/commission_card.dart';
import '../widgets/pay_commission_sheet.dart';
import '../widgets/payouts_list.dart';
import '../widgets/request_payout_sheet.dart';
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

class _ArtisanEarningsScreenState extends ConsumerState<ArtisanEarningsScreen> {
  EarningsPeriod _period = EarningsPeriod.week;

  @override
  Widget build(BuildContext context) {
    final summaryKey = EarningsSummaryKey(role: _kArtisanRole, period: _period);
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
                  summaryRefreshing: summaryAsync.isLoading ||
                      summaryAsync.isRefreshing ||
                      summaryAsync.isReloading,
                  summaryHasError: summaryAsync.hasError,
                  period: _period,
                  onPeriodChanged: (p) => setState(() => _period = p),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EarningsContent extends ConsumerWidget {
  const _EarningsContent({
    required this.summary,
    required this.summaryRefreshing,
    required this.summaryHasError,
    required this.period,
    required this.onPeriodChanged,
  });

  final EarningsSummary summary;
  final bool summaryRefreshing;
  final bool summaryHasError;
  final EarningsPeriod period;
  final ValueChanged<EarningsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Top headline mirrors the homepage "Earnings" tile so both surfaces
    // report the same Paystack-settled net for the active role. Falls back
    // to the summary endpoint while the today-card is still loading so the
    // balance card never flashes 0 unnecessarily.
    final user = ref.watch(currentUserProvider);
    final jobsDone = user?.artisanProfile?.completedJobsCount ?? 0;
    // "Available" must be the *withdrawable* balance — the sum of net
    // payments where the escrow is released and no transfer is in flight.
    // Previously this read `todayCard.netEarningsPesewas` which is just
    // today's earnings (includes money already paid out OR currently in
    // a retrying transfer), so the figure was misleading and the
    // Request Payout button gated on the wrong number.
    final availablePesewas = summary.effectiveBalancePesewas;
    final pendingPesewas = summary.pendingPayoutsPesewas;
    final isInArrears = summary.isInArrears;
    final canRequestPayout = canRequestPayoutFromSummary(
      summary: summary,
      summaryRefreshing: summaryRefreshing,
      summaryHasError: summaryHasError,
    );
    final available = availablePesewas / 100;
    final periodNet = summary.netEarningsPesewas / 100;

    // Commission, jobs count, and avg-fare follow the segmented control —
    // the screen reads as a coherent whole, not a half-period/half-week
    // mash-up. Riverpod caches by family key so each (role, period) pair
    // is fetched at most once until invalidated.
    final reportQuery = EarningsReportQuery.preset(
      role: _kArtisanRole,
      period: period,
    );
    final reportAsync = ref.watch(earningsReportProvider(reportQuery));
    final report = reportAsync.valueOrNull;

    // Pass the AsyncValue, not just `.valueOrNull ?? empty` — that
    // collapses every failure into the same "no chip" rendering as a
    // legitimate zero-rating state. The chip handles loading/error/empty
    // distinctly so a real backend failure surfaces visibly.
    final ratingsAsync = ref.watch(providerRatingsProvider);

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
          ratingsAsync: ratingsAsync,
          isInArrears: isInArrears,
        ),
        if (pendingPesewas > 0) ...[
          const SizedBox(height: MyShopSpacing.sm),
          // "Pending settlement" line — money the platform owes and is
          // currently trying to disburse. Includes payouts in `pending`,
          // `processing`, and `retrying` states. Without this surface
          // the artisan saw GHS 0 on the dashboard even though the
          // platform was actively retrying their MoMo transfer.
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MyShopSpacing.md,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.schedule,
                  size: 16, color: MyShopColors.primaryGoldDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pending settlement: GH₵ ${(pendingPesewas / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: MyShopSpacing.sm),
        // Action CTA — Pay Commission when in arrears, Request Payout when
        // there's a withdrawable balance, disabled otherwise. Mirrors the
        // driver dashboard so both roles share the same earnings UX.
        if (isInArrears)
          ElevatedButton.icon(
            onPressed: () => showPayCommissionSheet(
              context,
              owedPesewas: summary.cashCommissionOwedPesewas,
            ),
            icon: const Icon(Icons.payments_rounded, size: 18),
            label: const Text('PAY COMMISSION'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.error,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: canRequestPayout
                ? () => showRequestPayoutSheet(context)
                : null,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(
              summaryRefreshing
                  ? 'REFRESHING BALANCE'
                  : pendingPesewas > 0
                      ? 'PAYOUT IN PROGRESS'
                      : 'REQUEST PAYOUT',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.primaryGold,
              foregroundColor: MyShopColors.textOnPrimary,
              disabledBackgroundColor:
                  MyShopColors.primaryGold.withValues(alpha: 0.4),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        const SizedBox(height: MyShopSpacing.md),
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                label: _jobsLabel(period),
                value: '${report?.bookingsCompleted ?? 0}',
                subtitle: 'Completed',
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: _MiniStatCard(
                label: 'AVG FARE',
                value: report == null || report.bookingsCompleted == 0
                    ? '—'
                    : 'GH₵ ${(report.averageFarePesewas / 100).toStringAsFixed(2)}',
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

        // Commission & Tax — follows the period selector
        CommissionCard(
          grossPesewas: report?.grossEarningsPesewas ?? 0,
          commissionPesewas: report?.commissionChargedPesewas ?? 0,
          netPesewas: report?.netEarningsPesewas ?? 0,
          title: _commissionTitle(period),
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

  static String _jobsLabel(EarningsPeriod p) {
    switch (p) {
      case EarningsPeriod.today:
        return 'JOBS TODAY';
      case EarningsPeriod.week:
        return 'JOBS THIS WEEK';
      case EarningsPeriod.month:
        return 'JOBS THIS MONTH';
    }
  }

  static String _commissionTitle(EarningsPeriod p) {
    switch (p) {
      case EarningsPeriod.today:
        return 'Commission & Tax — Today';
      case EarningsPeriod.week:
        return 'Commission & Tax — This Week';
      case EarningsPeriod.month:
        return 'Commission & Tax — This Month';
    }
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
    required this.ratingsAsync,
    required this.isInArrears,
  });

  /// Effective balance — positive when payable, negative when the artisan
  /// owes pending cash-commission clawbacks. UI renders the absolute value
  /// when [isInArrears] is true and reframes the labelling accordingly.
  final double available;
  final double periodNet;
  final int jobsDone;
  final AsyncValue<ProviderRatingsSummary> ratingsAsync;
  final bool isInArrears;

  @override
  Widget build(BuildContext context) {
    final headline = isInArrears ? 'Owings' : 'Available Balance';
    final amountColor = isInArrears
        ? MyShopColors.error.withValues(alpha: 0.95)
        : MyShopColors.textOnDarkSlate;
    final magnitude = available.abs().toStringAsFixed(2);
    final amountText =
        isInArrears ? '−GH₵ $magnitude' : 'GH₵ ${available.toStringAsFixed(2)}';

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
              Icon(
                isInArrears
                    ? Icons.warning_amber_rounded
                    : Icons.account_balance_wallet_outlined,
                size: 16,
                color: isInArrears
                    ? MyShopColors.error
                    : MyShopColors.textOnDarkSlate.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headline,
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.textOnDarkSlate.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              _RatingChip(ratingsAsync: ratingsAsync),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            amountText,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: amountColor,
              height: 1.1,
            ),
          ),
          if (isInArrears) ...[
            const SizedBox(height: 4),
            Text(
              'Will be netted from your next in-app earnings',
              style: MyShopTypography.caption.copyWith(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
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
  const _RatingChip({required this.ratingsAsync});

  final AsyncValue<ProviderRatingsSummary> ratingsAsync;

  @override
  Widget build(BuildContext context) {
    // Four distinct states so a real failure isn't visually identical to
    // a freshly-onboarded artisan with zero revealed ratings.
    return ratingsAsync.when(
      loading: () => _chipShell(
        const _Glyph(icon: Icons.star_rounded, color: MyShopColors.primaryGold),
        const _ChipText('—'),
        null,
      ),
      error: (_, __) => _chipShell(
        const _Glyph(
          icon: Icons.error_outline,
          color: MyShopColors.error,
        ),
        const _ChipText("Couldn't load"),
        null,
      ),
      data: (r) {
        if (!r.hasRatings) {
          // Hide the chip entirely for the legitimate empty state — the
          // dashboard already conveys "new account" via other zero stats.
          return const SizedBox.shrink();
        }
        return _chipShell(
          const _Glyph(
            icon: Icons.star_rounded,
            color: MyShopColors.primaryGold,
          ),
          _ChipText(r.averageDisplay),
          '(${r.count})',
        );
      },
    );
  }

  Widget _chipShell(Widget glyph, Widget value, String? trailing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyph,
          const SizedBox(width: 4),
          value,
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Text(
              trailing,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textOnDarkSlate.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: 14, color: color);
}

class _ChipText extends StatelessWidget {
  const _ChipText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Raleway',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: MyShopColors.textOnDarkSlate,
        ),
      );
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
