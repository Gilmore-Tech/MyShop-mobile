import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../../driver_home/providers/driver_earnings_provider.dart';
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

    final todayAmount = earningsAsync.whenOrNull(data: (e) => e.todayAmountPesewas) ?? 0;
    final weekAmount = earningsAsync.whenOrNull(data: (e) => e.weekAmountPesewas) ?? 0;
    final todayTrips = earningsAsync.whenOrNull(data: (e) => e.todayTrips) ?? 0;
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
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFFCEAE1),
                      child: Icon(Icons.person,
                          size: 18, color: MyShopColors.textSecondary),
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
              child: _WeeklyPerformanceCard(),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Commission & Tax card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _CommissionCard(weekPesewas: weekAmount),
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
            // Empty state — no payouts endpoint wired yet
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: Container(
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
                    Text('No payouts yet',
                        style: MyShopTypography.body1.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: MyShopSpacing.xs),
                    Text('Your payout history will appear here',
                        style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.textSecondary)),
                  ],
                ),
              ),
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
        const WeeklyPerformanceChart(
          values: [115, 230, 200, 320, 460, 410, 175],
          maxValue: 460,
        ),
      ]),
    );
  }
}

extension on OutlinedButton {
  // No-op decorative extension to avoid icon left of label.
  OutlinedButton copyWithTrailingChevron() => this;
}

// ─── Commission card ────────────────────────────────────────────────────────

class _CommissionCard extends StatelessWidget {
  const _CommissionCard({required this.weekPesewas});
  final int weekPesewas;

  @override
  Widget build(BuildContext context) {
    final commission = (weekPesewas * 0.20).round();
    final net = weekPesewas - commission;

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
