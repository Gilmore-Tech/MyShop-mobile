import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Reusable list-tile row used inside the Account Settings hub.
///
/// Layout: [icon container] [title + subtitle] [optional trailing chip] [chevron]
class SettingsListTile extends StatelessWidget {
  const SettingsListTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingChipLabel,
    this.trailingChipColor,
    this.trailingChipBackground,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? trailingChipLabel;
  final Color? trailingChipColor;
  final Color? trailingChipBackground;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final iconColor = danger ? MyShopColors.error : MyShopColors.textPrimary;
    final titleColor = danger ? MyShopColors.error : MyShopColors.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.xs,
          vertical: MyShopSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color:
                    danger ? MyShopColors.errorLight : MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: MyShopTypography.body2.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailingChipLabel != null) ...[
              const SizedBox(width: MyShopSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: trailingChipBackground ??
                      (trailingChipColor ?? MyShopColors.primaryGold)
                          .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (trailingChipColor ?? MyShopColors.primaryGold)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  trailingChipLabel!,
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: trailingChipColor ?? MyShopColors.primaryGold,
                  ),
                ),
              ),
            ],
            if (!danger) ...[
              const SizedBox(width: MyShopSpacing.xs),
              const Icon(Icons.chevron_right,
                  size: 18, color: MyShopColors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}
