import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../trips/widgets/date_range_picker_modal.dart';
import '../widgets/weekly_performance_chart.dart';

/// Detailed earnings & payout reports.
///
/// Custom design built on the existing MyShop design system. Features:
///   - Date range filter (reuses DateRangePickerModal from trips feature)
///   - Period segmented control (Daily / Weekly / Monthly)
///   - Summary stat cards (Gross, Commission, Net, Trips, Avg Fare, Tips)
///   - Performance bar chart for the selected period
///   - Day-by-day breakdown table
///   - Export CTA
class EarningsReportsScreen extends StatefulWidget {
  const EarningsReportsScreen({super.key});

  @override
  State<EarningsReportsScreen> createState() => _EarningsReportsScreenState();
}

enum _Period { daily, weekly, monthly }

class _EarningsReportsScreenState extends State<EarningsReportsScreen> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  _Period _period = _Period.weekly;

  bool get _hasFilter => _rangeStart != null && _rangeEnd != null;

  String get _dateLabel {
    if (!_hasFilter) return 'All Time';
    final fmt = DateFormat('MMM dd');
    final yearFmt = DateFormat('MMM dd, yyyy');
    final start = _rangeStart!;
    final end = _rangeEnd!;
    if (start.year == end.year) {
      return '${fmt.format(start)} - ${yearFmt.format(end)}';
    }
    return '${yearFmt.format(start)} - ${yearFmt.format(end)}';
  }

  Future<void> _openDatePicker() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = await DateRangePickerModal.show(
      context,
      initialStart: _rangeStart ?? today.subtract(const Duration(days: 29)),
      initialEnd: _rangeEnd ?? today,
    );
    if (result != null) {
      setState(() {
        _rangeStart = result.start;
        _rangeEnd = result.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Reports',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                letterSpacing: -0.5)),
        titleSpacing: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: MyShopSpacing.md),
            child: IconButton(
              icon: const Icon(Icons.file_download_outlined,
                  size: 22, color: MyShopColors.textPrimary),
              onPressed: () {},
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(
              height: 0.5, thickness: 0.5, color: MyShopColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // ── Date filter pill ──
          GestureDetector(
            onTap: _openDatePicker,
            child: Container(
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
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.calendar_today_outlined,
                        size: 16, color: MyShopColors.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Date Range',
                              style: MyShopTypography.body2.copyWith(
                                  fontSize: 11,
                                  color: MyShopColors.textSecondary)),
                          Text(_dateLabel,
                              style: const TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: MyShopColors.textPrimary)),
                        ]),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: MyShopColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // ── Period segmented control ──
          _PeriodSegment(
            value: _period,
            onChanged: (v) => setState(() => _period = v),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── Summary stats ──
          Row(children: [
            Expanded(
                child: _SummaryCard(
                    label: 'GROSS',
                    value: 'GHS 1,850.00',
                    delta: '+8% vs prev')),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
                child: _SummaryCard(
                    label: 'NET',
                    value: 'GHS 1,480.00',
                    delta: '+12% vs prev',
                    highlight: true)),
          ]),
          const SizedBox(height: MyShopSpacing.sm),
          Row(children: [
            Expanded(
                child: _SummaryCard(
                    label: 'COMMISSION',
                    value: '- GHS 370.00',
                    delta: '20% rate')),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
                child: _SummaryCard(
                    label: 'TIPS',
                    value: 'GHS 65.00',
                    delta: '+₵12 vs prev')),
          ]),
          const SizedBox(height: MyShopSpacing.sm),
          Row(children: [
            Expanded(
                child: _SummaryCard(
                    label: 'TRIPS',
                    value: '42',
                    delta: '+5 vs prev')),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
                child: _SummaryCard(
                    label: 'AVG FARE',
                    value: 'GHS 44.05',
                    delta: '+₵2.30 vs prev')),
          ]),
          const SizedBox(height: MyShopSpacing.lg),

          // ── Performance chart ──
          Container(
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Earnings Trend',
                                style: TextStyle(
                                    fontFamily: 'Raleway',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: MyShopColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(_chartSubtitle,
                                style: MyShopTypography.body2.copyWith(
                                    fontSize: 11,
                                    color: MyShopColors.primaryGold,
                                    fontWeight: FontWeight.w600)),
                          ]),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: MyShopColors.successLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.trending_up,
                                size: 12, color: MyShopColors.success),
                            const SizedBox(width: 4),
                            Text('+12.4%',
                                style: TextStyle(
                                    fontFamily: 'Raleway',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: MyShopColors.success)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  WeeklyPerformanceChart(
                    values: _chartData,
                    maxValue: _chartMax,
                  ),
                ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── Breakdown table ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Daily Breakdown',
                  style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textPrimary)),
              Text('See All',
                  style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.primaryGold,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: MyShopSpacing.md, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12)),
                    border: Border(
                        bottom: BorderSide(
                            color: MyShopColors.divider, width: 0.5)),
                  ),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Text('DATE',
                            style: MyShopTypography.overline.copyWith(
                                fontSize: 10, letterSpacing: 0.6))),
                    Expanded(
                        flex: 2,
                        child: Text('TRIPS',
                            textAlign: TextAlign.right,
                            style: MyShopTypography.overline.copyWith(
                                fontSize: 10, letterSpacing: 0.6))),
                    Expanded(
                        flex: 4,
                        child: Text('NET',
                            textAlign: TextAlign.right,
                            style: MyShopTypography.overline.copyWith(
                                fontSize: 10, letterSpacing: 0.6))),
                  ]),
                ),
                _BreakdownRow(date: 'Mon, Oct 23', trips: 5, net: 'GHS 142.00'),
                _BreakdownRow(date: 'Tue, Oct 24', trips: 7, net: 'GHS 230.00'),
                _BreakdownRow(date: 'Wed, Oct 25', trips: 6, net: 'GHS 200.00'),
                _BreakdownRow(date: 'Thu, Oct 26', trips: 8, net: 'GHS 320.00'),
                _BreakdownRow(date: 'Fri, Oct 27', trips: 9, net: 'GHS 460.00'),
                _BreakdownRow(date: 'Sat, Oct 28', trips: 4, net: 'GHS 410.00'),
                _BreakdownRow(
                    date: 'Sun, Oct 29',
                    trips: 3,
                    net: 'GHS 175.00',
                    isLast: true),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── Export CTA ──
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Export PDF Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: MyShopColors.textOnPrimary,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Reports are stored for 24 months. Tax-ready format available.',
              style: MyShopTypography.caption.copyWith(fontSize: 10),
            ),
          ),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }

  String get _chartSubtitle {
    return switch (_period) {
      _Period.daily => 'Hourly earnings (last 24 hours)',
      _Period.weekly => 'Earnings across last 7 days',
      _Period.monthly => 'Earnings across last 4 weeks',
    };
  }

  List<double> get _chartData {
    return switch (_period) {
      _Period.daily => const [50, 80, 120, 90, 200, 250, 180],
      _Period.weekly => const [115, 230, 200, 320, 460, 410, 175],
      _Period.monthly => const [820, 1100, 1300, 1850, 1480, 950, 1700],
    };
  }

  double get _chartMax {
    return switch (_period) {
      _Period.daily => 280,
      _Period.weekly => 460,
      _Period.monthly => 2000,
    };
  }
}

// ─── Period segmented control ───────────────────────────────────────────────

class _PeriodSegment extends StatelessWidget {
  const _PeriodSegment({required this.value, required this.onChanged});
  final _Period value;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final p in _Period.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 36,
                  decoration: BoxDecoration(
                    color: p == value
                        ? MyShopColors.surfaceWhite
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: p == value
                        ? const [
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      switch (p) {
                        _Period.daily => 'Daily',
                        _Period.weekly => 'Weekly',
                        _Period.monthly => 'Monthly',
                      },
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight:
                            p == value ? FontWeight.w900 : FontWeight.w400,
                        color: p == value
                            ? MyShopColors.textPrimary
                            : MyShopColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Summary card ───────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.delta,
    this.highlight = false,
  });
  final String label;
  final String value;
  final String delta;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: highlight ? MyShopColors.darkSlate : MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight ? MyShopColors.darkSlate : MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: highlight ? Colors.white60 : MyShopColors.textSecondary,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: highlight ? Colors.white : MyShopColors.textPrimary,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 2),
          Text(delta,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: highlight ? Colors.white60 : MyShopColors.textSecondary,
              )),
        ],
      ),
    );
  }
}

// ─── Breakdown row ──────────────────────────────────────────────────────────

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.date,
    required this.trips,
    required this.net,
    this.isLast = false,
  });
  final String date;
  final int trips;
  final String net;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(
                    color: MyShopColors.divider, width: 0.5),
              ),
      ),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Text(date,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
        ),
        Expanded(
          flex: 2,
          child: Text('$trips',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.textSecondary)),
        ),
        Expanded(
          flex: 4,
          child: Text(net,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary)),
        ),
      ]),
    );
  }
}
