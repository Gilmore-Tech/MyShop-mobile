import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Online/offline status banner with toggle CTA.
///
/// Online: green-tinted background, success check, "You are Online" /
/// "Receiving live requests", dark "Go Offline" pill button.
///
/// While the parent is awaiting the verification + profile-completion
/// checks (set [isWorking] = true), the pill swaps its label for an
/// inline spinner so the user sees the call in flight rather than a
/// frozen-looking button.
class ArtisanOnlineBanner extends StatelessWidget {
  const ArtisanOnlineBanner({
    super.key,
    required this.isOnline,
    required this.onToggle,
    this.isWorking = false,
  });

  final bool isOnline;
  final VoidCallback onToggle;
  final bool isWorking;

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
                  isWorking
                      ? 'Checking your profile…'
                      : isOnline
                          ? 'Receiving live requests'
                          : 'Tap to start receiving jobs',
                  style: MyShopTypography.body2.copyWith(color: accent),
                ),
              ],
            ),
          ),

          // Toggle button — spinner replaces label while we're awaiting
          // verification + profile checks so the tap doesn't look ignored.
          GestureDetector(
            onTap: isWorking ? null : onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.darkSlate,
                borderRadius: BorderRadius.circular(24),
              ),
              child: isWorking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          MyShopColors.textOnDarkSlate,
                        ),
                      ),
                    )
                  : Text(
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
