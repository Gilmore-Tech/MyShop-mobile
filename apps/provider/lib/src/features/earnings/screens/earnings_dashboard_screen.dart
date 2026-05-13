import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../../profile/providers/verification_provider.dart';
import '../providers/earnings_providers.dart';
import '../providers/ratings_provider.dart';
import '../widgets/commission_card.dart';
import '../widgets/payouts_list.dart';
import '../widgets/weekly_performance_card.dart';

/// Earnings dashboard — balance card, stats, performance chart, commission, payouts.
///
/// Figma: node 213:12474
/// PRD Reference: PRD 5.4
///
/// Backed by two endpoints in parallel:
///   - summary (week)  → top balance card + sparkline + today/week mini stats
///   - report  (week)  → commission breakdown card
class EarningsDashboardScreen extends ConsumerWidget {
  const EarningsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(activeEarningsRoleProvider);
    final summaryKey =
        EarningsSummaryKey(role: role, period: EarningsPeriod.week);
    final reportQuery = EarningsReportQuery.preset(
      role: role,
      period: EarningsPeriod.week,
    );
    final summaryAsync = ref.watch(earningsSummaryProvider(summaryKey));
    final reportAsync = ref.watch(earningsReportProvider(reportQuery));
    final todayCardAsync = ref.watch(todayCardProvider(role));

    final photoState = ref.watch(localProfilePhotoProvider);
    final backendPhotoUrl = user?.profilePhotoUrl;
    final ImageProvider? avatarImage = photoState.localFile != null
        ? FileImage(photoState.localFile!)
        : (backendPhotoUrl ?? photoState.cloudinaryUrl) != null
            ? NetworkImage(backendPhotoUrl ?? photoState.cloudinaryUrl!)
            : null;

    final summary = summaryAsync.valueOrNull;
    final report = reportAsync.valueOrNull;
    final todayCard = todayCardAsync.valueOrNull;

    // The headline balance is the driver's actual payable cash — in-app
    // net MINUS pending cash-commission clawbacks. Goes negative when the
    // driver owes more commission than they've earned in-app; the card
    // below flips its label from "Available balance" to "Owings" and
    // shows the absolute value so the rider doesn't see "-GHS 1.80".
    final effectiveBalance = summary?.effectiveBalancePesewas ?? 0;
    final isInArrears = summary?.isInArrears ?? false;
    final todayAvailable = todayCard?.netEarningsPesewas ??
        summary?.todayAvailableBalancePesewas ??
        0;
    final weeklyAvailable = report?.netEarningsPesewas ??
        summary?.weeklyAvailableBalancePesewas ??
        0;
    final tripsCompleted = report?.bookingsCompleted ?? 0;
    final isVerified = user?.verificationStatus == 'approved';

    // Surface a clear failure banner instead of letting "API down" look
    // identical to "driver hasn't earned yet" — the dashboard's all-zeros
    // state was masking real production failures. Today-card now drives
    // the headline number, so its load state gates the banner alongside
    // the summary's.
    final loadError = todayCardAsync.hasError && summaryAsync.hasError;
    final isLoading = (todayCardAsync.isLoading && todayCard == null) &&
        (summaryAsync.isLoading && summary == null);

    // Branch on AsyncValue state explicitly so a real failure (auth lapse,
    // 5xx, parse error) reads as "Couldn't load ratings" instead of being
    // visually identical to a freshly-onboarded provider with zero
    // revealed ratings — that conflation was hiding production failures.
    final ratingsAsync = ref.watch(providerRatingsProvider);
    final (String ratingValue, String ratingSubtitle) = ratingsAsync.when(
      loading: () => ('—', 'Loading…'),
      error: (_, __) => ('!', "Couldn't load ratings"),
      data: (r) => r.hasRatings
          ? (
              r.averageDisplay,
              '${r.count} ${r.count == 1 ? 'review' : 'reviews'}',
            )
          : ('--', 'No ratings yet'),
    );

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(earningsSummaryProvider);
            ref.invalidate(earningsReportProvider);
            ref.invalidate(todayCardProvider);
            ref.invalidate(payoutsProvider);
            await Future.wait([
              ref.read(earningsSummaryProvider(summaryKey).future),
              ref.read(todayCardProvider(role).future),
            ]);
          },
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(MyShopSpacing.md,
                    MyShopSpacing.md, MyShopSpacing.md, MyShopSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Earnings',
                              style: TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: MyShopColors.textPrimary,
                                  letterSpacing: -0.5)),
                          Row(children: [
                            Icon(
                                isVerified
                                    ? Icons.check_circle_outline
                                    : Icons.access_time,
                                size: 12,
                                color: isVerified
                                    ? MyShopColors.success
                                    : MyShopColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                                isVerified
                                    ? 'Verified Provider'
                                    : 'Pending Verification',
                                style: MyShopTypography.body2
                                    .copyWith(fontSize: 11)),
                          ]),
                        ]),
                    Row(children: [
                      Stack(children: [
                        const Icon(Icons.notifications_outlined,
                            size: 24, color: MyShopColors.textPrimary),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: MyShopColors.error,
                                shape: BoxShape.circle),
                          ),
                        ),
                      ]),
                      const SizedBox(width: MyShopSpacing.md),
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFFCEAE1),
                        backgroundImage: avatarImage,
                        child: avatarImage == null
                            ? const Icon(Icons.person,
                                size: 18, color: MyShopColors.textSecondary)
                            : null,
                      ),
                    ]),
                  ],
                ),
              ),
              const Divider(
                  height: 0.5, thickness: 0.5, color: MyShopColors.divider),
              const SizedBox(height: MyShopSpacing.md),

              // Diagnostic banners — surface "API down" or "still loading"
              // states explicitly so the all-zeros render below is never
              // mistaken for genuine zero earnings.
              if (loadError)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                  child: _EarningsErrorBanner(
                    onRetry: () {
                      ref.invalidate(earningsSummaryProvider(summaryKey));
                      ref.invalidate(todayCardProvider(role));
                    },
                  ),
                )
              else if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                  child: _EarningsLoadingBanner(),
                ),
              if (loadError || isLoading)
                const SizedBox(height: MyShopSpacing.sm),

              // ── Balance card ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: _BalanceCard(
                  availablePesewas: effectiveBalance,
                  todayPesewas: todayAvailable,
                  weekPesewas: weeklyAvailable,
                  isInArrears: isInArrears,
                ),
              ),
              const SizedBox(height: MyShopSpacing.md),

              // ── Trips + Rating stats ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: Row(children: [
                  Expanded(
                      child: _StatCard(
                          icon: Icons.trending_up,
                          label: role == EarningsRole.driver ? 'TRIPS' : 'JOBS',
                          value: '$tripsCompleted',
                          subtitle: 'This week',
                          subtitleColor: MyShopColors.textSecondary)),
                  const SizedBox(width: MyShopSpacing.md),
                  Expanded(
                      child: _StatCard(
                          icon: Icons.star_rounded,
                          label: 'RATING',
                          value: ratingValue,
                          subtitle: ratingSubtitle,
                          subtitleColor: MyShopColors.textSecondary)),
                ]),
              ),
              const SizedBox(height: MyShopSpacing.md),

              // ── Performance chart (gap-filled daily series) ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: WeeklyPerformanceCard(
                  series: summary?.series ?? const [],
                  granularity: summary?.granularity ?? EarningsGranularity.day,
                  subtitle: 'Net earnings, last 7 days',
                ),
              ),
              const SizedBox(height: MyShopSpacing.md),

              // ── Commission & Tax card ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: CommissionCard(
                  grossPesewas: report?.grossEarningsPesewas ?? 0,
                  commissionPesewas: report?.commissionChargedPesewas ?? 0,
                  netPesewas: report?.netEarningsPesewas ?? 0,
                ),
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // ── Recent Payouts ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.history,
                          size: 18, color: MyShopColors.textPrimary),
                      const SizedBox(width: 6),
                      const Text('Recent Payouts',
                          style: TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: MyShopColors.textPrimary)),
                    ]),
                    Text('See All',
                        style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: MyShopSpacing.sm),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: PayoutsList(),
              ),
              const SizedBox(height: MyShopSpacing.md),

              // ── Payment Verification banner ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: Container(
                  padding: const EdgeInsets.all(MyShopSpacing.md),
                  decoration: BoxDecoration(
                    color: MyShopColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MyShopColors.primaryGold),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: MyShopColors.surfaceGrey,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.info_outline,
                            size: 16, color: MyShopColors.textPrimary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Payment Verification',
                                  style: TextStyle(
                                      fontFamily: 'Raleway',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: MyShopColors.textPrimary)),
                              const SizedBox(height: 4),
                              Text(
                                  'Standard bank transfers can take up to 24 hours. Use MoMo for instant availability. Contact support for disputes.',
                                  style: MyShopTypography.body2
                                      .copyWith(fontSize: 11, height: 1.5)),
                            ]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Diagnostic banners ─────────────────────────────────────────────────────

/// Surfaced when the summary endpoint is in error state — without it, the
/// dashboard's `?? 0` fallbacks would make an API outage look identical to
/// "driver has zero earnings", which is exactly how a recent prod
/// regression hid for hours.
class _EarningsErrorBanner extends StatelessWidget {
  const _EarningsErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: MyShopColors.error),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Couldn't load earnings — check the logs (tag: Earnings).",
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 28),
              foregroundColor: MyShopColors.error,
              textStyle: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EarningsLoadingBanner extends StatelessWidget {
  const _EarningsLoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: const [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          SizedBox(width: 10),
          Text(
            'Loading earnings…',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Balance card ───────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.availablePesewas,
    required this.todayPesewas,
    required this.weekPesewas,
    required this.isInArrears,
  });

  /// Effective balance — positive when payable, negative when the driver
  /// owes pending cash-commission clawbacks. UI renders the absolute value
  /// when [isInArrears] is true.
  final int availablePesewas;
  final int todayPesewas;
  final int weekPesewas;
  final bool isInArrears;

  @override
  Widget build(BuildContext context) {
    final totalDisplay = _fmtGhs(availablePesewas.abs());
    final todayDisplay = _fmtGhs(todayPesewas);
    final weekDisplay = _fmtGhs(weekPesewas);
    final headline = isInArrears ? 'Owings' : 'Available Balance';
    final badgeText = isInArrears ? 'Owes platform' : 'Active';
    final amountColor = isInArrears
        ? MyShopColors.error.withValues(alpha: 0.95)
        : Colors.white;

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.lg),
      decoration: BoxDecoration(
        color: MyShopColors.darkSlate,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(
              isInArrears
                  ? Icons.warning_amber_rounded
                  : Icons.account_balance_wallet_outlined,
              size: 16,
              color: isInArrears ? MyShopColors.error : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(headline,
                style: MyShopTypography.body2.copyWith(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isInArrears
                  ? MyShopColors.error.withValues(alpha: 0.15)
                  : Colors.white24,
              borderRadius: BorderRadius.circular(12),
              border: isInArrears
                  ? Border.all(color: MyShopColors.error, width: 1)
                  : null,
            ),
            child: Text(badgeText,
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isInArrears ? MyShopColors.error : Colors.white)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            // Prepend "-" when in arrears so the driver reads it as
            // "−GHS 3.60 owed" — the abs() above gives the magnitude.
            isInArrears ? '−GHS $totalDisplay' : 'GHS $totalDisplay',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: amountColor,
                letterSpacing: -0.8)),
        if (isInArrears) ...[
          const SizedBox(height: 4),
          Text('Will be netted from your next in-app earnings',
              style: MyShopTypography.caption.copyWith(
                  color: Colors.white70, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: MyShopSpacing.md),
        Row(children: [
          Expanded(
              child:
                  _BalanceMiniStat(label: 'TODAY', value: 'GHS $todayDisplay')),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
              child:
                  _BalanceMiniStat(label: 'WEEKLY', value: 'GHS $weekDisplay')),
        ]),
      ]),
    );
  }
}

class _BalanceMiniStat extends StatelessWidget {
  const _BalanceMiniStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white60,
                letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
      ]),
    );
  }
}

// ─── Stat card (Trips / Rating) ─────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.subtitleColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: MyShopColors.textSecondary),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 12),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: MyShopTypography.caption.copyWith(
                fontSize: 11,
                color: subtitleColor,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _fmtGhs(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble()) {
    return ghs.toStringAsFixed(0);
  }
  return ghs.toStringAsFixed(2);
}
