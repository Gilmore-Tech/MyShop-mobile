import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Recent activity list — currently shows an empty state since
/// the trip history endpoint is not yet integrated.
///
/// Figma: nodes 164:10493 → 164:10579
class RecentActivitySection extends StatelessWidget {
  const RecentActivitySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textPrimary,
                letterSpacing: 0.7,
                height: 1.43,
              ),
            ),
            GestureDetector(
              onTap: () {
                // TODO: Navigate to full activity list
              },
              child: Text(
                'See All',
                style: MyShopTypography.body2.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Empty state
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: MyShopColors.divider.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.directions_car_outlined,
                  size: 24,
                  color: MyShopColors.textSecondary,
                ),
              ),
              const SizedBox(height: MyShopSpacing.md),
              Text(
                'No trips yet',
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: MyShopSpacing.xs),
              Text(
                'Your completed trips will appear here',
                style: MyShopTypography.body2.copyWith(
                  color: MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
