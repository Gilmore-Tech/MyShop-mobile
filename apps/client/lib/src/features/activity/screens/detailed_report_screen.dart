import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/activity_history_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.6 — Detailed Report. Drills into the current month's spend with a
// type breakdown (rides vs jobs), status counts, and an average transaction.
// Reuses the same [activityHistoryProvider] the list screen builds, so the
// numbers match the hero "Spent in <Month>" total the user just tapped on.
//
// Style tokens — match `activity_list_screen.dart`:
//   - Raleway font family
//   - Card: 12dp radius + divider border + soft `0x0A000000` shadow
//   - Outer horizontal padding: w * 0.044

class DetailedReportScreen extends ConsumerWidget {
  const DetailedReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final state = ref.watch(activityHistoryProvider);

    // Flatten the grouped feed back to a single list and scope every metric
    // to the current calendar month so the report matches the "Spent in <X>"
    // total on the list screen.
    final now = DateTime.now();
    final allItems = state.groups.expand((g) => g.items).toList();
    final monthItems = allItems
        .where((i) =>
            i.createdAt.year == now.year && i.createdAt.month == now.month)
        .toList();

    final report = _Report.fromItems(
      monthItems,
      monthLabel: state.summary?.monthLabel ?? DateFormat.MMMM().format(now),
    );

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context, w),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: MyShopColors.primaryGold,
              ),
            )
          : monthItems.isEmpty
              ? _EmptyReport(monthLabel: report.monthLabel, w: w, h: h)
              : SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    w * 0.044,
                    h * 0.018,
                    w * 0.044,
                    h * 0.040,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroCard(report: report, w: w, h: h),
                      SizedBox(height: h * 0.018),
                      _BreakdownCard(report: report, w: w, h: h),
                      SizedBox(height: h * 0.018),
                      _StatsGrid(report: report, w: w, h: h),
                      SizedBox(height: h * 0.018),
                      _StatusSplitCard(report: report, w: w, h: h),
                    ],
                  ),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, double w) {
    return AppBar(
      backgroundColor: MyShopColors.surfaceWhite,
      surfaceTintColor: MyShopColors.surfaceWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded,
            color: MyShopColors.textPrimary),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        'Detailed Report',
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.050,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
          height: 1.3,
        ),
      ),
      centerTitle: false,
    );
  }
}

// ── Report model ──────────────────────────────────────────────────────────────

class _Report {
  final String monthLabel;
  final int totalPesewas;
  final int rideTotalPesewas;
  final int jobTotalPesewas;
  final int rideCount;
  final int jobCount;
  final int completedCount;
  final int cancelledCount;
  final int inProgressCount;
  final int pendingCount;

  const _Report({
    required this.monthLabel,
    required this.totalPesewas,
    required this.rideTotalPesewas,
    required this.jobTotalPesewas,
    required this.rideCount,
    required this.jobCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.inProgressCount,
    required this.pendingCount,
  });

  factory _Report.fromItems(
    List<TransactionItem> items, {
    required String monthLabel,
  }) {
    var rideTotal = 0;
    var jobTotal = 0;
    var rideCount = 0;
    var jobCount = 0;
    var completed = 0;
    var cancelled = 0;
    var inProgress = 0;
    var pending = 0;

    for (final i in items) {
      if (i.type == TransactionType.ride) {
        rideTotal += i.amountPesewas;
        rideCount += 1;
      } else {
        jobTotal += i.amountPesewas;
        jobCount += 1;
      }
      switch (i.status) {
        case TransactionStatus.completed:
          completed += 1;
        case TransactionStatus.cancelled:
          cancelled += 1;
        case TransactionStatus.inProgress:
          inProgress += 1;
        case TransactionStatus.pending:
          pending += 1;
      }
    }

    return _Report(
      monthLabel: monthLabel,
      totalPesewas: rideTotal + jobTotal,
      rideTotalPesewas: rideTotal,
      jobTotalPesewas: jobTotal,
      rideCount: rideCount,
      jobCount: jobCount,
      completedCount: completed,
      cancelledCount: cancelled,
      inProgressCount: inProgress,
      pendingCount: pending,
    );
  }

  int get totalCount => rideCount + jobCount;

  int get averagePerTxnPesewas =>
      totalCount == 0 ? 0 : (totalPesewas / totalCount).round();

  double get rideShare =>
      totalPesewas == 0 ? 0 : rideTotalPesewas / totalPesewas;

  double get jobShare => totalPesewas == 0 ? 0 : jobTotalPesewas / totalPesewas;

  static String formatPesewas(int pesewas) {
    final ghs = pesewas / 100.0;
    final intPart = ghs.floor();
    final decPart = ((ghs - intPart) * 100).round();
    final formatted = intPart.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return 'GH¢ $formatted.${decPart.toString().padLeft(2, '0')}';
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final _Report report;
  final double w, h;
  const _HeroCard({required this.report, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.051, vertical: h * 0.026),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MyShopColors.darkSlate, Color(0xFF2C3640)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: w * 0.041, color: MyShopColors.primaryGold),
              SizedBox(width: w * 0.020),
              Expanded(
                child: Text(
                  'TOTAL SPENT IN ${report.monthLabel.toUpperCase()}',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.026,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.surfaceWhite.withValues(alpha: 0.85),
                    letterSpacing: 1.0,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.012),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _Report.formatPesewas(report.totalPesewas),
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.092,
                fontWeight: FontWeight.w700,
                color: MyShopColors.surfaceWhite,
                height: 1.15,
                letterSpacing: -0.5,
              ),
            ),
          ),
          SizedBox(height: h * 0.014),
          Wrap(
            spacing: w * 0.020,
            runSpacing: h * 0.008,
            children: [
              _HeroChip(
                icon: Icons.receipt_long_rounded,
                label: '${report.totalCount} '
                    '${report.totalCount == 1 ? 'transaction' : 'transactions'}',
                w: w,
              ),
              _HeroChip(
                icon: Icons.trending_up_rounded,
                label:
                    'Avg ${_Report.formatPesewas(report.averagePerTxnPesewas)}',
                w: w,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double w;
  const _HeroChip({required this.icon, required this.label, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.026, vertical: w * 0.013),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: w * 0.033, color: MyShopColors.surfaceWhite),
          SizedBox(width: w * 0.013),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.028,
              fontWeight: FontWeight.w600,
              color: MyShopColors.surfaceWhite,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Breakdown by type ─────────────────────────────────────────────────────────

class _BreakdownCard extends StatelessWidget {
  final _Report report;
  final double w, h;
  const _BreakdownCard(
      {required this.report, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      w: w,
      h: h,
      title: 'Spending by type',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BreakdownRow(
            color: MyShopColors.primaryGold,
            label: 'Rides',
            countLabel:
                '${report.rideCount} ${report.rideCount == 1 ? 'trip' : 'trips'}',
            amount: _Report.formatPesewas(report.rideTotalPesewas),
            share: report.rideShare,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.014),
          _BreakdownRow(
            color: MyShopColors.darkSlate,
            label: 'Artisan jobs',
            countLabel:
                '${report.jobCount} ${report.jobCount == 1 ? 'job' : 'jobs'}',
            amount: _Report.formatPesewas(report.jobTotalPesewas),
            share: report.jobShare,
            w: w,
            h: h,
          ),
          if (report.totalPesewas > 0) ...[
            SizedBox(height: h * 0.018),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(
                      flex: (report.rideShare * 1000).round(),
                      child: Container(color: MyShopColors.primaryGold),
                    ),
                    Expanded(
                      flex: (report.jobShare * 1000).round(),
                      child: Container(color: MyShopColors.darkSlate),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final Color color;
  final String label;
  final String countLabel;
  final String amount;
  final double share;
  final double w, h;
  const _BreakdownRow({
    required this.color,
    required this.label,
    required this.countLabel,
    required this.amount,
    required this.share,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (share * 100).round();
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: w * 0.026),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.036,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                  height: 1.3,
                ),
              ),
              SizedBox(height: h * 0.002),
              Text(
                '$countLabel · $percent%',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: w * 0.020),
        Text(
          amount,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: w * 0.038,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

// ── Stats grid (4 tiles) ──────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final _Report report;
  final double w, h;
  const _StatsGrid({required this.report, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _StatTileData(
        icon: Icons.receipt_long_rounded,
        label: 'Transactions',
        value: '${report.totalCount}',
        color: MyShopColors.info,
      ),
      _StatTileData(
        icon: Icons.check_circle_outline_rounded,
        label: 'Completed',
        value: '${report.completedCount}',
        color: MyShopColors.success,
      ),
      _StatTileData(
        icon: Icons.cancel_outlined,
        label: 'Cancelled',
        value: '${report.cancelledCount}',
        color: MyShopColors.error,
      ),
      _StatTileData(
        icon: Icons.trending_up_rounded,
        label: 'Avg / txn',
        value: _Report.formatPesewas(report.averagePerTxnPesewas),
        color: MyShopColors.primaryGold,
        isLong: true,
      ),
    ];

    return Row(
      children: [
        Expanded(child: _StatTile(data: tiles[0], w: w, h: h)),
        SizedBox(width: w * 0.022),
        Expanded(child: _StatTile(data: tiles[1], w: w, h: h)),
        SizedBox(width: w * 0.022),
        Expanded(child: _StatTile(data: tiles[2], w: w, h: h)),
        SizedBox(width: w * 0.022),
        Expanded(child: _StatTile(data: tiles[3], w: w, h: h)),
      ],
    );
  }
}

class _StatTileData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isLong;
  const _StatTileData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.isLong = false,
  });
}

class _StatTile extends StatelessWidget {
  final _StatTileData data;
  final double w, h;
  const _StatTile({required this.data, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.022, vertical: h * 0.014),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: w * 0.044, color: data.color),
          SizedBox(height: h * 0.008),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: data.isLong ? w * 0.030 : w * 0.044,
                fontWeight: FontWeight.w800,
                color: MyShopColors.textPrimary,
                height: 1.15,
              ),
            ),
          ),
          SizedBox(height: h * 0.003),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.024,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status split card ─────────────────────────────────────────────────────────

class _StatusSplitCard extends StatelessWidget {
  final _Report report;
  final double w, h;
  const _StatusSplitCard(
      {required this.report, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final entries = <_StatusEntry>[
      if (report.completedCount > 0)
        _StatusEntry(
          status: TransactionStatus.completed,
          count: report.completedCount,
        ),
      if (report.inProgressCount > 0)
        _StatusEntry(
          status: TransactionStatus.inProgress,
          count: report.inProgressCount,
        ),
      if (report.pendingCount > 0)
        _StatusEntry(
          status: TransactionStatus.pending,
          count: report.pendingCount,
        ),
      if (report.cancelledCount > 0)
        _StatusEntry(
          status: TransactionStatus.cancelled,
          count: report.cancelledCount,
        ),
    ];

    return _SectionCard(
      w: w,
      h: h,
      title: 'Status breakdown',
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _StatusRow(entry: entries[i], w: w, h: h),
            if (i < entries.length - 1) SizedBox(height: h * 0.012),
          ],
        ],
      ),
    );
  }
}

class _StatusEntry {
  final TransactionStatus status;
  final int count;
  const _StatusEntry({required this.status, required this.count});
}

class _StatusRow extends StatelessWidget {
  final _StatusEntry entry;
  final double w, h;
  const _StatusRow({required this.entry, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: w * 0.082,
          height: w * 0.082,
          decoration: BoxDecoration(
            color: entry.status.badgeBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            entry.status.badgeIcon,
            size: w * 0.041,
            color: entry.status.badgeFg,
          ),
        ),
        SizedBox(width: w * 0.031),
        Expanded(
          child: Text(
            entry.status.label,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.036,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
              height: 1.3,
            ),
          ),
        ),
        Text(
          '${entry.count}',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: w * 0.041,
            fontWeight: FontWeight.w800,
            color: MyShopColors.textPrimary,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

// ── Shared section card ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final double w, h;
  const _SectionCard({
    required this.title,
    required this.child,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044, vertical: h * 0.020),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.038,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textPrimary,
              height: 1.3,
            ),
          ),
          SizedBox(height: h * 0.014),
          child,
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyReport extends StatelessWidget {
  final String monthLabel;
  final double w, h;
  const _EmptyReport({
    required this.monthLabel,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: w * 0.205,
              height: w * 0.205,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bar_chart_rounded,
                size: w * 0.092,
                color: MyShopColors.textSecondary,
              ),
            ),
            SizedBox(height: h * 0.022),
            Text(
              'No activity in $monthLabel yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.040,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                height: 1.3,
              ),
            ),
            SizedBox(height: h * 0.008),
            Text(
              'Once you book a ride or hire an artisan, your spending '
              'breakdown shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.032,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
