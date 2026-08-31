import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/widgets/provider_status_dot.dart';
import '../../notifications/widgets/provider_notification_bell.dart';

/// Top header for the Artisan Home screen.
///
/// Layout: Business name + region (left) | Notification bell + avatar (right)
class ArtisanHomeHeader extends StatelessWidget {
  const ArtisanHomeHeader({
    super.key,
    required this.businessName,
    required this.region,
    this.avatarUrl,
    this.localAvatarFile,
    this.onAvatarTap,
  });

  final String businessName;
  final String region;
  final String? avatarUrl;
  final File? localAvatarFile;
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
                      Icons.handyman_outlined,
                      size: 14,
                      color: MyShopColors.primaryGold,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        region.toUpperCase(),
                        style: MyShopTypography.overline.copyWith(
                          color: MyShopColors.primaryGold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const ProviderNotificationBell(contained: true),
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
                    image: localAvatarFile != null
                        ? DecorationImage(
                            image: FileImage(localAvatarFile!),
                            fit: BoxFit.cover,
                          )
                        : avatarUrl != null
                            ? DecorationImage(
                                image: NetworkImage(avatarUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                  ),
                  child: localAvatarFile == null && avatarUrl == null
                      ? const Icon(
                          Icons.person,
                          color: MyShopColors.textSecondary,
                        )
                      : null,
                ),
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: ProviderStatusDot(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
