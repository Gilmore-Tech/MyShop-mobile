import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Read-only snapshot card for the artisan-home "Live Job Feed" carousel.
///
/// Intentionally non-interactive (no [GestureDetector], no [onTap], no
/// ripple) — these cards exist purely to signal platform liveness, not as
/// a personal task list. Targeted job requests still surface via the
/// existing full-screen modal.
class LiveFeedSnapshotCard extends StatelessWidget {
  const LiveFeedSnapshotCard({
    super.key,
    required this.categoryName,
    required this.areaLabel,
    required this.timeAgo,
    this.distanceKm,
  });

  final String categoryName;
  final String areaLabel;
  final String timeAgo;
  final double? distanceKm;

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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top row: live dot + category
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: MyShopColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text(
                  categoryName,
                  style: MyShopTypography.h3.copyWith(
                    color: MyShopColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Middle row: area
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  areaLabel,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Bottom row: time-ago left, distance right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                timeAgo,
                style: MyShopTypography.caption.copyWith(
                  color: MyShopColors.textSecondary,
                ),
              ),
              if (distanceKm != null)
                Text(
                  _formatKm(distanceKm!),
                  style: MyShopTypography.caption.copyWith(
                    color: MyShopColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatKm(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }
}
