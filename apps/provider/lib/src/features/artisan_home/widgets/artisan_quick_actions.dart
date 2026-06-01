import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Row of 3 quick action tiles: Schedule, Inbox, Payout.
class ArtisanQuickActions extends StatelessWidget {
  const ArtisanQuickActions({
    super.key,
    this.onSchedule,
    this.onInbox,
    this.onPayout,
  });

  final VoidCallback? onSchedule;
  final VoidCallback? onInbox;
  final VoidCallback? onPayout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.calendar_today_outlined,
              label: 'Schedule',
              onTap: onSchedule,
            ),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: _ActionTile(
              icon: Icons.chat_bubble_outline,
              label: 'Inbox',
              onTap: onInbox,
            ),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: _ActionTile(
              icon: Icons.north_east,
              label: 'Payout',
              onTap: onPayout,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: MyShopColors.textPrimary),
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              label,
              style: MyShopTypography.body1.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
