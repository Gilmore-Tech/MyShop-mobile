import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Inline notice shown wherever provider profile details are displayed.
///
/// Providers can view their information but cannot edit it — name, email,
/// photo, vehicle and business details are all changed by an admin on
/// request. This note replaces the former "Edit" entry points.
class ProfileReadOnlyNote extends StatelessWidget {
  const ProfileReadOnlyNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.sm),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline,
              size: 14, color: MyShopColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Your profile details are read-only. To update them, contact '
              'support and an admin will make the change for you.',
              style: MyShopTypography.body2.copyWith(fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
