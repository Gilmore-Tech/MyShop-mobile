import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../router.dart';

/// Canonical bottom navigation bar for the 4 main tabs.
///
/// Used directly by [MainShell] (in-shell tab switching via
/// `navigationShell.goBranch`) and by full-screen routes pushed above the
/// shell (via `context.go` to the tab's root path).
///
/// Keep this as the single source of truth for the nav's icons, labels,
/// and styling — do not paint a local copy inside individual screens.
enum AppTab { home, services, activity, profile }

class AppBottomNav extends StatelessWidget {
  final AppTab                activeTab;
  final void Function(AppTab) onTap;

  const AppBottomNav({
    super.key,
    required this.activeTab,
    required this.onTap,
  });

  /// Convenience constructor for screens that live above the shell:
  /// taps trigger `context.go(...)` to the relevant tab root.
  factory AppBottomNav.routing({
    Key? key,
    required BuildContext context,
    required AppTab activeTab,
  }) {
    return AppBottomNav(
      key: key,
      activeTab: activeTab,
      onTap: (tab) => context.go(_routeFor(tab)),
    );
  }

  static String _routeFor(AppTab tab) {
    switch (tab) {
      case AppTab.home:     return AppRoutes.home;
      case AppTab.services: return AppRoutes.services;
      case AppTab.activity: return AppRoutes.activity;
      case AppTab.profile:  return AppRoutes.profile;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset:     const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(
                icon:     Icons.location_on_outlined,
                label:    'Home',
                isActive: activeTab == AppTab.home,
                onTap:    () => onTap(AppTab.home),
              ),
              _NavItem(
                icon:     Icons.handyman_outlined,
                label:    'Services',
                isActive: activeTab == AppTab.services,
                onTap:    () => onTap(AppTab.services),
              ),
              _NavItem(
                icon:     Icons.access_time_outlined,
                label:    'Activity',
                isActive: activeTab == AppTab.activity,
                onTap:    () => onTap(AppTab.activity),
              ),
              _NavItem(
                icon:     Icons.person_outline,
                label:    'Profile',
                isActive: activeTab == AppTab.profile,
                onTap:    () => onTap(AppTab.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final bool         isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? MyShopColors.primaryGold : MyShopColors.darkSlate;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize:   10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color:      color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
