import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/widgets/provider_status_dot.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../profile/providers/verification_provider.dart';

/// Frosted-glass header with welcome text and avatar.
///
/// Figma: node 164:10627
/// - backdrop-blur 6px, white 80% opacity
/// - 128dp height
/// - Bottom border line
class DriverHomeHeader extends ConsumerWidget {
  const DriverHomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPadding = MediaQuery.of(context).padding.top;
    final user = ref.watch(currentUserProvider);
    final profilePhoto = ref.watch(providerProfilePhotoDisplayProvider);
    final ImageProvider? avatarImage = profilePhoto.localFile != null
        ? FileImage(profilePhoto.localFile!)
        : profilePhoto.url != null
            ? NetworkImage(profilePhoto.url!)
            : null;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          height: topPadding + 88,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite.withValues(alpha: 0.8),
            border: const Border(
              bottom: BorderSide(color: MyShopColors.divider, width: 0.5),
            ),
          ),
          padding: EdgeInsets.only(
            top: topPadding,
            left: MyShopSpacing.md,
            right: MyShopSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Welcome text + driver name
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WELCOME BACK',
                      style: MyShopTypography.overline.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user?.displayName ?? 'Driver',
                      style: MyShopTypography.h3.copyWith(fontSize: 18),
                    ),
                  ],
                ),
              ),

              // Avatar with online dot
              Stack(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCEAE1),
                      borderRadius: BorderRadius.circular(20),
                      image: avatarImage != null
                          ? DecorationImage(
                              image: avatarImage,
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: avatarImage == null
                        ? const ClipOval(
                            child: Icon(
                              Icons.person,
                              size: 24,
                              color: MyShopColors.textSecondary,
                            ),
                          )
                        : null,
                  ),
                  // Status indicator — green/orange/red/grey based on the
                  // provider's online state + ability to go online.
                  const Positioned(
                    bottom: 0.86,
                    right: 0.86,
                    child: ProviderStatusDot(size: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
