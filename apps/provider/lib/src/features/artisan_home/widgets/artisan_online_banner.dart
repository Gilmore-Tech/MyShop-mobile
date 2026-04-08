import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Online/offline status banner with toggle CTA.
///
/// Online: green-tinted background, success check, "You are Online" /
/// "Receiving live requests", dark "Go Offline" pill button.
class ArtisanOnlineBanner extends StatelessWidget {
  const ArtisanOnlineBanner({
    super.key,
    required this.isOnline,
    required this.onToggle,
  });

  final bool isOnline;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bg = isOnline ? MyShopColors.successLight : MyShopColors.surfaceGrey;
    final accent = isOnline ? MyShopColors.success : MyShopColors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.md,
      ),
      color: bg,
      child: Row(
        children: [
          // Status icon (filled circle with check)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 18,
              color: MyShopColors.textOnPrimary,
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),

          // Status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOnline ? 'You are Online' : 'You are Offline',
                  style: MyShopTypography.h3.copyWith(color: accent),
                ),
                const SizedBox(height: 2),
                Text(
                  isOnline
                      ? 'Receiving live requests'
                      : 'Tap to start receiving jobs',
                  style: MyShopTypography.body2.copyWith(color: accent),
                ),
              ],
            ),
          ),

          // Toggle button
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.darkSlate,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                isOnline ? 'Go Offline' : 'Go Online',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textOnDarkSlate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
