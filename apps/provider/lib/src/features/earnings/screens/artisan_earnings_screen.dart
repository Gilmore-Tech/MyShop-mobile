import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Artisan-side earnings details screen.
///
/// PRD Reference: PRD 5.4 — provider earnings & payouts.
class ArtisanEarningsScreen extends StatefulWidget {
  const ArtisanEarningsScreen({super.key});

  @override
  State<ArtisanEarningsScreen> createState() => _ArtisanEarningsScreenState();
}

class _ArtisanEarningsScreenState extends State<ArtisanEarningsScreen> {
  _Period _period = _Period.weekly;

  // Mock data
  static const _weeklyTrend = [180, 200, 220, 410, 320, 580, 420];
  static const _availableBalance = 1840.50;
  static const _totalRevenue = 12400;
  static const _jobsDone = 42;
  static const _tipsEarned = 142.00;
  static const _platformFees = 88.20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                ),
                children: [
                  _PeriodSegmented(
                    value: _period,
                    onChanged: (p) => setState(() => _period = p),
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _BalanceCard(
                    available: _availableBalance,
                    totalRevenue: _totalRevenue,
                    jobsDone: _jobsDone,
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _IncomeTrendCard(values: _weeklyTrend.map((e) => e.toDouble()).toList()),
                  const SizedBox(height: MyShopSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStatCard(
                          label: 'TIPS EARNED',
                          value: 'GH₵ ${_tipsEarned.toStringAsFixed(2)}',
                          subtitle: '8% of total income',
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.md),
                      Expanded(
                        child: _MiniStatCard(
                          label: 'PLATFORM FEES',
                          value: 'GH₵ ${_platformFees.toStringAsFixed(2)}',
                          subtitle: 'Standard 5% rate',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recent Activity',
                          style: MyShopTypography.h2.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          'View All',
                          style: MyShopTypography.body1.copyWith(
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  const _ActivityRow(
                    name: 'Kofi Mensah',
                    service: 'Electrical Wiring',
                    timestamp: 'Oct 24, 2:30 PM',
                    amount: 'GH₵ 150.00',
                  ),
                  const Divider(height: 1, color: MyShopColors.divider),
                  const _ActivityRow(
                    name: 'Ama Serwaa',
                    service: 'Plumbing Maintenance',
                    timestamp: 'Oct 23, 11:15 AM',
                    amount: 'GH₵ 85.50',
                  ),
                  const Divider(height: 1, color: MyShopColors.divider),
                  const _ActivityRow(
                    name: 'John Doe',
                    service: 'Aircon Service',
                    timestamp: 'Oct 22, 4:45 PM',
                    amount: 'GH₵ 210.00',
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  const _TaxReportCard(),
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
            _PayoutFooter(onTap: () {}),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Period segmented control
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Balance card
// ─────────────────────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.available,
    required this.totalRevenue,
    required this.jobsDone,
  });

  final double available;
  final num totalRevenue;
  final int jobsDone;

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
                    color: MyShopColors.textOnDarkSlate.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Verified',
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textOnDarkSlate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
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
                  label: 'TOTAL REVENUE',
                  value: 'GH₵ ${totalRevenue.toString()}',
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

// ─────────────────────────────────────────────────────────────────────────────
// Income trend chart
// ─────────────────────────────────────────────────────────────────────────────

class _IncomeTrendCard extends StatelessWidget {
  const _IncomeTrendCard({required this.values});

  final List<double> values;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Income Trend',
                      style: MyShopTypography.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Visualizing your growth this week',
                      style: MyShopTypography.body2,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.successLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 14,
                      color: MyShopColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '+12.4%',
                      style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 600,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 150,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: MyShopColors.divider,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 150,
                      getTitlesWidget: (value, _) {
                        if (value == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            value.toInt().toString(),
                            style: MyShopTypography.caption.copyWith(
                              color: MyShopColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= _days.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _days[i],
                            style: MyShopTypography.caption.copyWith(
                              color: MyShopColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < values.length; i++)
                        FlSpot(i.toDouble(), values[i]),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: MyShopColors.primaryGold,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          MyShopColors.primaryGold.withValues(alpha: 0.35),
                          MyShopColors.primaryGold.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini stat card (Tips / Platform Fees)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Activity row
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.name,
    required this.service,
    required this.timestamp,
    required this.amount,
  });

  final String name;
  final String service;
  final String timestamp;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: MyShopColors.avatarPlaceholder,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: MyShopColors.textSecondary),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: MyShopTypography.h3.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(service, style: MyShopTypography.body2),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 12,
                      color: MyShopColors.primaryGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timestamp,
                      style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.primaryGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+$amount',
                style: MyShopTypography.h3.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: MyShopColors.success,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'CLEARED',
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.success,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tax report banner
// ─────────────────────────────────────────────────────────────────────────────

class _TaxReportCard extends StatelessWidget {
  const _TaxReportCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceWhite,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 22,
              color: MyShopColors.primaryGold,
            ),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tax Report Ready',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your Q3 summary is now available for download.',
                  style: MyShopTypography.body2.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: MyShopColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payout footer
// ─────────────────────────────────────────────────────────────────────────────

class _PayoutFooter extends StatelessWidget {
  const _PayoutFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                  'Settlement usually takes 2-4 hours',
                  style: MyShopTypography.body2,
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: Text(
                  'View Terms',
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.primaryGold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: MyShopColors.darkSlate,
                borderRadius: BorderRadius.circular(28),
              ),
              alignment: Alignment.center,
              child: Text(
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
