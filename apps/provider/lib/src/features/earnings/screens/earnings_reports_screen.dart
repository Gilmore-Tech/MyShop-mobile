import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../../trips/widgets/date_range_picker_modal.dart';
import '../data/earnings_report_pdf.dart';
import '../providers/earnings_providers.dart';
import '../widgets/earnings_line_chart.dart';
import '../widgets/weekly_performance_chart.dart';

/// Detailed earnings & payout reports.
///
/// Wires `GET /v1/payments/earnings/report` in two modes:
///   - Preset (Daily/Weekly/Monthly tabs) → `?period=today|week|month`
///   - Custom date range (date picker)    → `?from=YYYY-MM-DD&to=YYYY-MM-DD`
///
/// Custom ranges are capped at 90 days server-side. We disable picker
/// selections beyond that range so users can't trigger
/// `EARNINGS_RANGE_TOO_LARGE`, but render the inline error if the backend
/// returns it anyway (e.g. clock skew, picker bug).
class EarningsReportsScreen extends ConsumerStatefulWidget {
  const EarningsReportsScreen({super.key});

  @override
  ConsumerState<EarningsReportsScreen> createState() =>
      _EarningsReportsScreenState();
}

class _EarningsReportsScreenState extends ConsumerState<EarningsReportsScreen> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  EarningsPeriod _preset = EarningsPeriod.week;
  bool _isExporting = false;

  bool get _isCustomRange => _rangeStart != null && _rangeEnd != null;

  String get _dateLabel {
    if (!_isCustomRange) {
      switch (_preset) {
        case EarningsPeriod.today:
          return 'Today';
        case EarningsPeriod.week:
          return 'Last 7 days';
        case EarningsPeriod.month:
          return 'Last 30 days';
      }
    }
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
      initialStart: _rangeStart ?? today.subtract(const Duration(days: 6)),
      initialEnd: _rangeEnd ?? today,
    );
    if (result != null) {
      setState(() {
        _rangeStart = result.start;
        _rangeEnd = result.end;
      });
    }
  }

  void _selectPreset(EarningsPeriod period) {
    setState(() {
      _preset = period;
      _rangeStart = null;
      _rangeEnd = null;
    });
  }

  EarningsReportQuery _buildQuery(EarningsRole role) {
    if (_isCustomRange) {
      return EarningsReportQuery.range(
        role: role,
        from: _rangeStart!,
        to: _rangeEnd!,
      );
    }
    return EarningsReportQuery.preset(role: role, period: _preset);
  }

  /// Filename slug like `myshop-earnings-driver-2026-04-19.pdf` so multiple
  /// exports don't collide on the user's device and the role+date is
  /// recoverable from the filename alone.
  String _exportFilename(EarningsRole role) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'myshop-earnings-${role.wire}-$today.pdf';
  }

  Future<void> _exportPdf({
    required EarningsReport report,
    required EarningsRole role,
  }) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final user = ref.read(currentUserProvider);
      final bytes = await EarningsReportPdf.build(
        report: report,
        role: role,
        dateLabel: _dateLabel,
        providerName: user?.displayName,
        providerPhone: user?.phone,
      );
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: _exportFilename(role),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't export the report. Please try again."),
          backgroundColor: MyShopColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(activeEarningsRoleProvider);
    final query = _buildQuery(role);
    final reportAsync = ref.watch(earningsReportProvider(query));

    // Disable export until the report has actually loaded — sharing a PDF
    // built from null/loading state would just send an empty document.
    final report = reportAsync.valueOrNull;
    final canExport = report != null && !_isExporting;
    final onExportTap =
        canExport ? () => _exportPdf(report: report, role: role) : null;

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
              tooltip: 'Export PDF',
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            MyShopColors.textPrimary),
                      ),
                    )
                  : Icon(
                      Icons.file_download_outlined,
                      size: 22,
                      color: canExport
                          ? MyShopColors.textPrimary
                          : MyShopColors.textSecondary,
                    ),
              onPressed: onExportTap,
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child:
              Divider(height: 0.5, thickness: 0.5, color: MyShopColors.divider),
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
                  if (_isCustomRange)
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: MyShopColors.textSecondary),
                      onPressed: () => setState(() {
                        _rangeStart = null;
                        _rangeEnd = null;
                      }),
                    )
                  else
                    const Icon(Icons.chevron_right,
                        size: 18, color: MyShopColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // ── Period segmented control (preset mode only) ──
          if (!_isCustomRange) ...[
            _PeriodSegment(
              value: _preset,
              onChanged: _selectPreset,
            ),
            const SizedBox(height: MyShopSpacing.lg),
          ],

          // ── Body — switches on report state ──
          reportAsync.when(
            loading: () => const _ReportSkeleton(),
            error: (e, _) => _ReportErrorBanner(
              error: e,
              onRetry: () => ref.invalidate(earningsReportProvider(query)),
            ),
            data: (report) => _ReportBody(
              report: report,
              role: role,
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── Export CTA ──
          ElevatedButton.icon(
            onPressed: onExportTap,
            icon: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          MyShopColors.textOnPrimary),
                    ),
                  )
                : const Icon(Icons.file_download_outlined, size: 16),
            label: Text(_isExporting ? 'Preparing PDF…' : 'Export PDF Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: MyShopColors.textOnPrimary,
              disabledBackgroundColor:
                  MyShopColors.darkSlate.withValues(alpha: 0.4),
              disabledForegroundColor: MyShopColors.textOnPrimary,
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
}

// ─── Body — report rendering ────────────────────────────────────────────────

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.role});

  final EarningsReport report;
  final EarningsRole role;

  @override
  Widget build(BuildContext context) {
    final bookingsLabel = role == EarningsRole.driver ? 'TRIPS' : 'JOBS';
    final trendBadge = _trendBadge(report.trendPct);

    return Column(
      children: [
        // ── Summary stats ──
        Row(children: [
          Expanded(
              child: _SummaryCard(
                  label: 'GROSS',
                  value: 'GHS ${_fmtGhs(report.grossEarningsPesewas)}',
                  delta: 'Includes cash & in-app')),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
              child: _SummaryCard(
                  label: 'NET',
                  value: 'GHS ${_fmtGhs(report.netEarningsPesewas)}',
                  delta: 'After commission',
                  highlight: true)),
        ]),
        const SizedBox(height: MyShopSpacing.sm),
        // TIPS card dropped 2026-05-13 — no tip surface exists in the
        // rider app today, so the value was always GHS 0.00 and undermined
        // trust in the rest of the dashboard.
        Row(children: [
          Expanded(
              child: _SummaryCard(
                  label: 'COMMISSION',
                  value: 'GHS ${_fmtGhs(report.commissionChargedPesewas)}',
                  delta: 'Recorded total')),
        ]),
        const SizedBox(height: MyShopSpacing.sm),
        Row(children: [
          Expanded(
              child: _SummaryCard(
                  label: bookingsLabel,
                  value: '${report.bookingsCompleted}',
                  delta: 'Completed')),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
              child: _SummaryCard(
                  label: 'AVG FARE',
                  value: report.bookingsCompleted == 0
                      ? '—'
                      : 'GHS ${_fmtGhs(report.averageFarePesewas)}',
                  delta: 'Per booking')),
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Earnings Trend',
                      style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: MyShopColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(_chartSubtitle(report.granularity),
                      style: MyShopTypography.body2.copyWith(
                          fontSize: 11,
                          color: MyShopColors.primaryGold,
                          fontWeight: FontWeight.w600)),
                ]),
                if (trendBadge != null) trendBadge,
              ],
            ),
            const SizedBox(height: MyShopSpacing.md),
            _ReportChart(report: report),
          ]),
        ),
        const SizedBox(height: MyShopSpacing.lg),

        // ── Bookings breakdown — line graph of count per bucket ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_granularityLabel(report.granularity)} '
              '${role == EarningsRole.driver ? 'Trips' : 'Jobs'}',
              style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textPrimary,
              ),
            ),
            Text(
              '${report.bookingsCompleted} total',
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.sm),
        _BreakdownLineChart(
          report: report,
          role: role,
        ),
      ],
    );
  }

  static String _chartSubtitle(EarningsGranularity g) {
    switch (g) {
      case EarningsGranularity.day:
        return 'Daily buckets';
      case EarningsGranularity.week:
        return 'Weekly buckets';
      case EarningsGranularity.month:
        return 'Monthly buckets';
    }
  }

  static String _granularityLabel(EarningsGranularity g) {
    switch (g) {
      case EarningsGranularity.day:
        return 'Daily';
      case EarningsGranularity.week:
        return 'Weekly';
      case EarningsGranularity.month:
        return 'Monthly';
    }
  }

  static Widget? _trendBadge(double? trendPct) {
    if (trendPct == null) return null;
    final isUp = trendPct >= 0;
    final color = isUp ? MyShopColors.success : MyShopColors.error;
    final bg = isUp ? MyShopColors.successLight : MyShopColors.errorLight;
    final sign = isUp ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isUp ? Icons.trending_up : Icons.trending_down,
              size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$sign${trendPct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportChart extends StatelessWidget {
  const _ReportChart({required this.report});

  final EarningsReport report;

  @override
  Widget build(BuildContext context) {
    if (report.series.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'No data for this period',
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final values =
        report.series.map((p) => p.netPesewas / 100).toList(growable: false);
    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxValue == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'No earnings in this period',
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      );
    }

    final labels = _xLabels(report.series, report.granularity);
    return WeeklyPerformanceChart(
      values: values,
      maxValue: (maxValue * 1.15).ceilToDouble(),
      xLabels: labels,
    );
  }

  static List<String> _xLabels(
      List<EarningsReportPoint> points, EarningsGranularity g) {
    const weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const month = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return points.map((p) {
      final d = p.bucketStart.toLocal();
      switch (g) {
        case EarningsGranularity.day:
          if (points.length <= 7) {
            return weekday[(d.weekday - 1).clamp(0, 6)];
          }
          return '${d.day}';
        case EarningsGranularity.week:
          return '${d.month}/${d.day}';
        case EarningsGranularity.month:
          return month[(d.month - 1).clamp(0, 11)];
      }
    }).toList(growable: false);
  }
}

/// Bookings count over time, rendered as a smooth line graph. Replaces the
/// old date/count/net table — at a glance the user sees the trend; tapping
/// a point reveals the exact date and count for that bucket.
class _BreakdownLineChart extends StatelessWidget {
  const _BreakdownLineChart({required this.report, required this.role});

  final EarningsReport report;
  final EarningsRole role;

  @override
  Widget build(BuildContext context) {
    final series = report.series;
    final countLabel = role == EarningsRole.driver ? 'trips' : 'jobs';

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: _buildChart(series, countLabel),
    );
  }

  Widget _buildChart(List<EarningsReportPoint> series, String countLabel) {
    if (series.isEmpty) {
      return _empty('No data for this period');
    }

    final values =
        series.map((p) => p.count.toDouble()).toList(growable: false);
    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxValue == 0) {
      return _empty('No completed $countLabel in this period');
    }

    return EarningsLineChart(
      values: values,
      // Pad by 15% so the topmost point isn't pinned to the chart's top
      // edge, then round up to a clean integer (counts are whole numbers).
      maxValue: (maxValue * 1.15).ceilToDouble(),
      xLabels: _xLabels(series, report.granularity),
      tooltipBuilder: (i) {
        final p = series[i];
        final count = p.count;
        return '${_formatBucketDate(p.bucketStart, report.granularity)}'
            ' · $count $countLabel';
      },
    );
  }

  Widget _empty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          message,
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
          ),
        ),
      ),
    );
  }

  static List<String> _xLabels(
      List<EarningsReportPoint> points, EarningsGranularity g) {
    const weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const month = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return points.map((p) {
      final d = p.bucketStart.toLocal();
      switch (g) {
        case EarningsGranularity.day:
          if (points.length <= 7) {
            return weekday[(d.weekday - 1).clamp(0, 6)];
          }
          return '${d.day}';
        case EarningsGranularity.week:
          return '${d.month}/${d.day}';
        case EarningsGranularity.month:
          return month[(d.month - 1).clamp(0, 11)];
      }
    }).toList(growable: false);
  }

  static String _formatBucketDate(DateTime utc, EarningsGranularity g) {
    final local = utc.toLocal();
    switch (g) {
      case EarningsGranularity.day:
        return DateFormat('EEE, MMM d').format(local);
      case EarningsGranularity.week:
        return 'Week of ${DateFormat('MMM d').format(local)}';
      case EarningsGranularity.month:
        return DateFormat('MMM yyyy').format(local);
    }
  }
}

// ─── Period segmented control ───────────────────────────────────────────────

class _PeriodSegment extends StatelessWidget {
  const _PeriodSegment({required this.value, required this.onChanged});
  final EarningsPeriod value;
  final ValueChanged<EarningsPeriod> onChanged;

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
          for (final p in EarningsPeriod.values)
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
                      _label(p),
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

  static String _label(EarningsPeriod p) {
    switch (p) {
      case EarningsPeriod.today:
        return 'Daily';
      case EarningsPeriod.week:
        return 'Weekly';
      case EarningsPeriod.month:
        return 'Monthly';
    }
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

// ─── Loading + error states ─────────────────────────────────────────────────

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: MyShopColors.shimmerBase,
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return Column(
      children: [
        Row(children: [
          Expanded(child: box(double.infinity, 80)),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(child: box(double.infinity, 80)),
        ]),
        const SizedBox(height: MyShopSpacing.sm),
        Row(children: [
          Expanded(child: box(double.infinity, 80)),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(child: box(double.infinity, 80)),
        ]),
        const SizedBox(height: MyShopSpacing.lg),
        box(double.infinity, 220),
      ],
    );
  }
}

class _ReportErrorBanner extends StatelessWidget {
  const _ReportErrorBanner({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = _messageFor(error);
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 18, color: MyShopColors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
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

  static String _messageFor(Object e) {
    if (e is EarningsApiException) {
      switch (e.code) {
        case EarningsErrorCodes.rangeTooLarge:
          return 'Custom ranges are capped at 90 days. Pick a shorter window.';
        case EarningsErrorCodes.rangeInvalid:
          return 'Pick a valid start and end date — the end must be on or after the start.';
        case EarningsErrorCodes.rangeAmbiguous:
          return 'Pick either a preset or a custom range, not both.';
        case EarningsErrorCodes.providerNotFound:
          return "We couldn't find a provider profile for this role. Switch role or finish onboarding.";
        case EarningsErrorCodes.roleNotResolved:
          return "We couldn't tell which role to load. Pick a role and try again.";
      }
    }
    return "Couldn't load report — pull to retry.";
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _fmtGhs(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble()) return ghs.toStringAsFixed(0);
  return ghs.toStringAsFixed(2);
}
