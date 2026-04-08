import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Top header for the Artisan Home screen.
///
/// Layout: Business name + region (left) | Notification bell + avatar (right)
class ArtisanHomeHeader extends StatelessWidget {
  const ArtisanHomeHeader({
    super.key,
    required this.businessName,
    required this.region,
    this.hasUnreadNotifications = false,
    this.avatarUrl,
    this.onNotificationsTap,
    this.onAvatarTap,
  });

  final String businessName;
  final String region;
  final bool hasUnreadNotifications;
  final String? avatarUrl;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Business name + region
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  businessName.toUpperCase(),
                  style: MyShopTypography.h1.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: MyShopColors.primaryGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      region.toUpperCase(),
                      style: MyShopTypography.overline.copyWith(
                        color: MyShopColors.primaryGold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Notification bell with red dot
          GestureDetector(
            onTap: onNotificationsTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                shape: BoxShape.circle,
                border: Border.all(color: MyShopColors.divider),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_none,
                    size: 22,
                    color: MyShopColors.textPrimary,
                  ),
                  if (hasUnreadNotifications)
                    Positioned(
                      top: 8,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: MyShopColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MyShopColors.surfaceWhite,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),

          // Avatar with online dot
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MyShopColors.avatarPlaceholder,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: MyShopColors.divider,
                      width: 1.5,
                    ),
                    image: avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(avatarUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatarUrl == null
                      ? const Icon(
                          Icons.person,
                          color: MyShopColors.textSecondary,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: MyShopColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: MyShopColors.surfaceWhite,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
