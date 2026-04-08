import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// "PERFORMANCE SUMMARY" section showing 3 stat cards in a 2-column grid:
/// Earnings, Avg Rating (highlighted gold), Job Done.
class PerformanceSummarySection extends StatelessWidget {
  const PerformanceSummarySection({
    super.key,
    required this.earnings,
    required this.earningsTrend,
    required this.rating,
    required this.ratingPercentile,
    required this.jobsDone,
    this.onDetailsTap,
  });

  final String earnings;
  final String earningsTrend;
  final String rating;
  final String ratingPercentile;
  final int jobsDone;
  final VoidCallback? onDetailsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Expanded(
                child: Text(
                  'PERFORMANCE SUMMARY',
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDetailsTap,
                child: Text(
                  'Details',
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.primaryGold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Stat cards — 2 columns, wraps to next row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'EARNINGS',
                  value: 'GHS $earnings',
                  trend: earningsTrend,
                ),
              ),
              const SizedBox(width: MyShopSpacing.md),
              Expanded(
                child: _StatCard(
                  icon: Icons.star_border,
                  label: 'AVG RATING',
                  value: rating,
                  trend: ratingPercentile,
                  highlighted: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle_outline,
                  label: 'JOB DONE',
                  value: '$jobsDone',
                ),
              ),
              const SizedBox(width: MyShopSpacing.md),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.trend,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? trend;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: highlighted
            ? MyShopColors.primaryGoldLight
            : MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + label row
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Value + trend
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: MyShopTypography.h2.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trend != null) ...[
                const Icon(
                  Icons.trending_up,
                  size: 14,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(width: 2),
                Text(
                  trend!,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),

          Text(
            'Updated now',
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.primaryGold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
