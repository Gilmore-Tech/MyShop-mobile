import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Bottom navigation bar for the driver app.
///
/// Figma: node 167:10755
/// - 4 tabs: Home (active, gold), Earnings (badge: 9), Trips, Account
/// - Frosted glass bg (white 95%, blur 8)
/// - Top border line
class DriverBottomNavBar extends StatelessWidget {
  const DriverBottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        border: Border(
          top: BorderSide(color: MyShopColors.divider, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavTab(
                icon: Icons.dashboard_outlined,
                label: 'Home',
                isActive: true,
              ),
              _NavTab(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Earnings',
                badgeCount: 9,
              ),
              _NavTab(
                icon: Icons.history,
                label: 'Trips',
              ),
              _NavTab(
                icon: Icons.account_circle_outlined,
                label: 'Account',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? MyShopColors.primaryGold : MyShopColors.textSecondary;

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon with optional badge
          if (badgeCount != null && badgeCount! > 0)
            Badge(
              label: Text(
                '$badgeCount',
                style: const TextStyle(fontSize: 8, color: Colors.white),
              ),
              backgroundColor: MyShopColors.error,
              child: Icon(icon, size: 24, color: color),
            )
          else
            Icon(icon, size: 24, color: color),

          const SizedBox(height: 4),

          // Label
          Text(
            label,
            style: TextStyle(
              fontFamily: isActive ? 'Raleway' : 'Raleway',
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
              color: color,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
