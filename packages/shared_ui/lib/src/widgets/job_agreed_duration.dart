import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_radius.dart';
import '../theme/myshop_spacing.dart';
import '../theme/myshop_typography.dart';

/// Displays the duration agreed during artisan bidding.
///
/// This intentionally does not count upward. It is the agreed plan and sits
/// alongside [JobElapsedTime], which reports the actual time spent on the job.
class JobAgreedDuration extends StatelessWidget {
  const JobAgreedDuration({
    super.key,
    required this.durationLabel,
    this.compact = false,
  });

  final String durationLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (durationLabel.trim().isEmpty ||
        durationLabel == 'Not specified' ||
        durationLabel == '—') {
      return const SizedBox.shrink();
    }

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_available_outlined,
            size: 16,
            color: MyShopColors.primaryGold,
          ),
          const SizedBox(width: 6),
          Text(
            'Agreed duration',
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            durationLabel,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MyShopRadius.card),
        border: Border.all(
          color: MyShopColors.primaryGold.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.event_available_outlined,
            size: 18,
            color: MyShopColors.primaryGold,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'Agreed duration',
              style: MyShopTypography.overline.copyWith(
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
          Text(
            durationLabel,
            style: MyShopTypography.h3.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
