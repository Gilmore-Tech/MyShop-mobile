import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';

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
    final photoUrl = user?.driverProfile?.profilePhotoUrl;

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
                      user?.fullName ?? 'Driver',
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
                      image: photoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(photoUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: photoUrl == null
                        ? const ClipOval(
                            child: Icon(
                              Icons.person,
                              size: 24,
                              color: MyShopColors.textSecondary,
                            ),
                          )
                        : null,
                  ),
                  // Green online indicator
                  Positioned(
                    bottom: 0.86,
                    right: 0.86,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: MyShopColors.online,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: MyShopColors.surfaceWhite,
                          width: 1.5,
                        ),
                      ),
                    ),
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
