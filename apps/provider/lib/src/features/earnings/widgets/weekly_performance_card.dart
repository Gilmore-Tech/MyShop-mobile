import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'weekly_performance_chart.dart';

/// Card wrapping the weekly bar chart with the section title, "View Reports"
/// CTA, and an empty-state when the user has no activity this week.
///
/// Folds the backend's per-hour `peakHours` rows into a 7-day count
/// (Mon..Sun) so the chart can render without each caller repeating the
/// remap. The backend reports `dayOfWeek` in Postgres' Sun=0..Sat=6
/// convention; the chart's visual order is Mon=0..Sun=6.
///
/// Shared between the driver and artisan earnings screens — both backends
/// return the same `peakHours` shape so the card is fully reusable.
class WeeklyPerformanceCard extends StatelessWidget {
  const WeeklyPerformanceCard({
    super.key,
    required this.peakHours,
    this.subtitle = 'Earnings across last 7 days',
    this.emptyLabel = 'No activity yet this week',
  });

  final List<EarningsPeakHour> peakHours;
  final String subtitle;
  final String emptyLabel;

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
                      'Weekly Performance',
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
          if (maxCount == 0)
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
              values: counts,
              // Round up to a clean tick so the topmost bar isn't pinned to
              // the top edge of the chart.
              maxValue: (maxCount * 1.15).ceilToDouble(),
            ),
        ],
      ),
    );
  }
}
