import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../../driver_home/data/earnings_service.dart';
import '../../driver_home/providers/driver_earnings_provider.dart';
import '../../profile/providers/verification_provider.dart';
import '../widgets/weekly_performance_chart.dart';

/// Earnings dashboard — balance card, stats, weekly chart, commission, payouts.
///
/// Figma: node 213:12474
/// PRD Reference: PRD 5.4
class EarningsDashboardScreen extends ConsumerWidget {
  const EarningsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final earningsAsync = ref.watch(driverEarningsProvider);
    final photoState = ref.watch(localProfilePhotoProvider);
    final backendPhotoUrl = user?.profilePhotoUrl;
    final ImageProvider? avatarImage = photoState.localFile != null
        ? FileImage(photoState.localFile!)
        : (backendPhotoUrl ?? photoState.cloudinaryUrl) != null
            ? NetworkImage(backendPhotoUrl ?? photoState.cloudinaryUrl!)
            : null;

    final todayAmount = earningsAsync.whenOrNull(data: (e) => e.todayAmountPesewas) ?? 0;
    final weekAmount = earningsAsync.whenOrNull(data: (e) => e.weekAmountPesewas) ?? 0;
    final weekCommission =
        earningsAsync.whenOrNull(data: (e) => e.weekCommissionPesewas) ?? 0;
    final weekNet = earningsAsync.whenOrNull(data: (e) => e.weekNetPesewas) ?? 0;
    final todayTrips = earningsAsync.whenOrNull(data: (e) => e.todayTrips) ?? 0;
    final peakHours =
        earningsAsync.whenOrNull(data: (e) => e.peakHours) ?? const [];
    final isVerified = user?.verificationStatus == 'approved';

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md, MyShopSpacing.md, MyShopSpacing.md, MyShopSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Earnings',
                        style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary,
                            letterSpacing: -0.5)),
                    Row(children: [
                      Icon(
                          isVerified ? Icons.check_circle_outline : Icons.access_time,
                          size: 12,
                          color: isVerified ? MyShopColors.success : MyShopColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(isVerified ? 'Verified Provider' : 'Pending Verification',
                          style: MyShopTypography.body2.copyWith(fontSize: 11)),
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

            // ── Balance card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _BalanceCard(
                todayPesewas: todayAmount,
                weekPesewas: weekAmount,
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Trips + Rating stats ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: Row(children: [
                Expanded(
                    child: _StatCard(
                        icon: Icons.trending_up,
                        label: 'TRIPS',
                        value: '$todayTrips',
                        subtitle: 'Today',
                        subtitleColor: MyShopColors.textSecondary)),
                const SizedBox(width: MyShopSpacing.md),
                const Expanded(
                    child: _StatCard(
                        icon: Icons.access_time,
                        label: 'RATING',
                        value: '--',
                        subtitle: 'No ratings yet',
                        subtitleColor: MyShopColors.textSecondary)),
              ]),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Weekly performance chart ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _WeeklyPerformanceCard(peakHours: peakHours),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Commission & Tax card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _CommissionCard(
                weekPesewas: weekAmount,
                weekCommissionPesewas: weekCommission,
                weekNetPesewas: weekNet,
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // ── Recent Payouts ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
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
              child: _PayoutsList(),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Payment Verification banner ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
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
    );
  }
}

// ─── Balance card ───────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.todayPesewas,
    required this.weekPesewas,
  });
  final int todayPesewas;
  final int weekPesewas;

  @override
  Widget build(BuildContext context) {
    final totalDisplay = _fmtGhs(todayPesewas + weekPesewas);
    final todayDisplay = _fmtGhs(todayPesewas);
    final weekDisplay = _fmtGhs(weekPesewas);

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.lg),
      decoration: BoxDecoration(
        color: MyShopColors.darkSlate,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text('Available Balance',
                style: MyShopTypography.body2.copyWith(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Active',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('GHS $totalDisplay',
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.8)),
        const SizedBox(height: MyShopSpacing.md),
        Row(children: [
          Expanded(
              child: _BalanceMiniStat(label: 'TODAY', value: 'GHS $todayDisplay')),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
              child: _BalanceMiniStat(label: 'WEEKLY', value: 'GHS $weekDisplay')),
        ]),
        const SizedBox(height: MyShopSpacing.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.surfaceWhite,
              foregroundColor: MyShopColors.textPrimary,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
            child: const Text('Request Instant MoMo Payout'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '*Instant payouts usually arrive in 5 minutes via Flutterwave',
            style: MyShopTypography.caption.copyWith(
                fontSize: 10,
                color: Colors.white54,
                fontStyle: FontStyle.italic),
          ),
        ),
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

// ─── Weekly performance card ────────────────────────────────────────────────

class _WeeklyPerformanceCard extends StatelessWidget {
  const _WeeklyPerformanceCard({required this.peakHours});

  /// One row per hour-of-week the backend has activity for. Empty list
  /// renders the chart with no bars (driver hasn't earned yet this week).
  final List<EarningsPeakHour> peakHours;

  /// Folds the per-hour rows into a 7-day count (Mon..Sun) so the existing
  /// bar chart can render real data instead of the hardcoded mock values.
  /// Backend reports `dayOfWeek` in Postgres' Sun=0..Sat=6 convention; we
  /// remap to Mon=0..Sun=6 to match the chart's visual order.
  List<double> get _weeklyCounts {
    final perDay = List<double>.filled(7, 0);
    for (final row in peakHours) {
      // Postgres Sun=0..Sat=6 → Mon=0..Sun=6 (Sun maps to slot 6).
      final mondayIndex = (row.dayOfWeek + 6) % 7;
      perDay[mondayIndex] += row.count.toDouble();
    }
    return perDay;
  }

  @override
  Widget build(BuildContext context) {
    final counts = _weeklyCounts;
    final maxCount = counts.fold<double>(0, (m, v) => v > m ? v : m);
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Weekly Performance',
                  style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textPrimary)),
              const SizedBox(height: 2),
              Text('Earnings across last 7 days',
                  style: MyShopTypography.body2.copyWith(
                      fontSize: 11,
                      color: MyShopColors.primaryGold,
                      fontWeight: FontWeight.w600)),
            ]),
            OutlinedButton.icon(
              onPressed: () => context.push('/earnings/reports'),
              label: const Text('View Reports'),
              icon: const SizedBox.shrink(),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.textPrimary,
                side: const BorderSide(color: MyShopColors.divider),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ).copyWithTrailingChevron(),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),
        if (maxCount == 0)
          // No rides yet this week — render a calm empty state instead
          // of a flat chart that looks broken.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'No rides yet this week',
                style: MyShopTypography.body2.copyWith(
                  color: MyShopColors.textSecondary,
                ),
              ),
            ),
          )
        else
          WeeklyPerformanceChart(
            values: counts,
            // Round up to a clean tick so the topmost bar isn't pinned to
            // the top edge of the chart.
            maxValue: (maxCount * 1.15).ceilToDouble(),
          ),
      ]),
    );
  }
}

extension on OutlinedButton {
  // No-op decorative extension to avoid icon left of label.
  OutlinedButton copyWithTrailingChevron() => this;
}

// ─── Payouts list ──────────────────────────────────────────────────────────

class _PayoutsList extends ConsumerWidget {
  const _PayoutsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payouts = ref.watch(driverPayoutsProvider);
    return payouts.when(
      loading: () => const _PayoutsEmpty(
        title: 'Loading payouts…',
        subtitle: 'Fetching the most recent transfers',
      ),
      error: (_, __) => const _PayoutsEmpty(
        title: "Couldn't load payouts",
        subtitle: 'Pull down to retry',
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const _PayoutsEmpty(
            title: 'No payouts yet',
            subtitle: 'Your payout history will appear here',
          );
        }
        return Column(
          children: [
            for (final row in rows.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PayoutRow(payout: row),
              ),
          ],
        );
      },
    );
  }
}

class _PayoutsEmpty extends StatelessWidget {
  const _PayoutsEmpty({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.history,
                size: 20, color: MyShopColors.textSecondary),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            title,
            style:
                MyShopTypography.body1.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: MyShopSpacing.xs),
          Text(
            subtitle,
            style: MyShopTypography.body2
                .copyWith(color: MyShopColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout});

  final DriverPayout payout;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatDate(payout.createdAt);
    final statusColor = _statusColor(payout.status);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smartphone,
                size: 18, color: MyShopColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _methodLabel(payout.method),
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: MyShopTypography.body2.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                payout.amountDisplay,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                payout.status.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'success':
      case 'succeeded':
      case 'completed':
        return MyShopColors.success;
      case 'failed':
      case 'declined':
        return MyShopColors.error;
      default:
        return MyShopColors.textSecondary;
    }
  }

  static String _methodLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'momo':
      case 'mobile_money':
      case 'momo_mtn':
        return 'MTN MoMo';
      case 'momo_telecel':
        return 'Telecel Cash';
      case 'momo_airteltigo':
        return 'AirtelTigo Money';
      case 'card':
        return 'Card payout';
      case 'bank':
        return 'Bank transfer';
      default:
        return raw.isEmpty ? 'Payout' : raw;
    }
  }

  static String _formatDate(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} · $hh:$mm';
  }
}

// ─── Commission card ────────────────────────────────────────────────────────

class _CommissionCard extends StatelessWidget {
  const _CommissionCard({
    required this.weekPesewas,
    required this.weekCommissionPesewas,
    required this.weekNetPesewas,
  });

  final int weekPesewas;

  /// Commission already reported by the backend's `/payments/earnings`
  /// (sum of `commissionPesewas` on Payment rows for this driver this
  /// week). Falls back to a 20% estimate of [weekPesewas] when the
  /// backend hasn't yet recorded any commission — e.g. fresh-driver
  /// case where the response carries an empty totals.
  final int weekCommissionPesewas;
  final int weekNetPesewas;

  @override
  Widget build(BuildContext context) {
    final commission = weekCommissionPesewas > 0
        ? weekCommissionPesewas
        : (weekPesewas * 0.20).round();
    final net = weekNetPesewas > 0
        ? weekNetPesewas
        : weekPesewas - commission;

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.swap_horiz,
              size: 18, color: MyShopColors.textPrimary),
          const SizedBox(width: 6),
          const Text('Commission & Tax',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Text('Auto-deducted',
                style: MyShopTypography.body2.copyWith(
                    fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: MyShopSpacing.md),
        _CommissionRow(label: 'App Commission (20%)', value: '- GHS ${_fmtGhs(commission)}'),
        const SizedBox(height: 12),
        const Divider(height: 1, thickness: 0.5, color: MyShopColors.divider),
        const SizedBox(height: 12),
        _CommissionRow(
            label: 'Net Earnings', value: 'GHS ${_fmtGhs(net)}', bold: true),
      ]),
    );
  }
}

class _CommissionRow extends StatelessWidget {
  const _CommissionRow(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
                color: bold ? MyShopColors.textPrimary : MyShopColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                color: MyShopColors.textPrimary)),
      ],
    );
  }
}

// ─── Helpers ─���──────────────────────────────────────────────────────────────

String _fmtGhs(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble()) {
    return ghs.toStringAsFixed(0);
  }
  return ghs.toStringAsFixed(2);
}
