import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'weekly_performance_chart.dart';

/// Card wrapping the bar chart with the section title, "View Reports" CTA,
/// and an empty-state when the user has no activity in the given window.
///
/// Backed by the gap-filled `series[]` from
/// `GET /v1/payments/earnings/summary` (or any caller that gives us a list
/// of `(bucketStart, netPesewas)` points). Backend already inserts
/// zero-net buckets for inactive days, so callers can pass the response
/// straight through.
///
/// Shared between the driver and artisan earnings screens.
class WeeklyPerformanceCard extends StatelessWidget {
  const WeeklyPerformanceCard({
    super.key,
    required this.series,
    required this.granularity,
    this.subtitle = 'Earnings across the selected period',
    this.emptyLabel = 'No activity yet this period',
  });

  /// Gap-filled series — one bucket per [granularity] step. May be empty.
  final List<EarningsSummaryPoint> series;

  /// Drives the X-axis label format (Mon..Sun for day, week numbers for
  /// week, month names for month).
  final EarningsGranularity granularity;

  final String subtitle;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final values =
        series.map((p) => p.netPesewas / 100).toList(growable: false);
    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Performance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MyShopTypography.body2.copyWith(
                        fontSize: 11,
                        color: MyShopColors.primaryGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              OutlinedButton(
                onPressed: () => context.push('/earnings/reports'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MyShopColors.textPrimary,
                  side: const BorderSide(color: MyShopColors.divider),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('View Reports'),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          if (series.isEmpty || maxValue == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  emptyLabel,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            WeeklyPerformanceChart(
              values: values,
              maxValue: (maxValue * 1.15).ceilToDouble(),
              xLabels: _xLabels(series, granularity),
            ),
        ],
      ),
    );
  }

  /// Picks a label format that fits the bucket cadence:
  ///   - day: 3-letter weekday for ≤7 buckets, day-of-month otherwise.
  ///   - week: ISO week start as "M/d".
  ///   - month: 3-letter month name.
  static List<String> _xLabels(
      List<EarningsSummaryPoint> points, EarningsGranularity g) {
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
