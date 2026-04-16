import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/app_bottom_nav.dart';

/// Persistent shell that wraps the four main tabs.
/// Renders the current branch body via [navigationShell] and shows
/// the shared [AppBottomNav] that survives tab switches.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        activeTab: AppTab.values[navigationShell.currentIndex],
        onTap: (tab) => navigationShell.goBranch(
          tab.index,
          // Re-tapping the active tab pops back to the branch root.
          initialLocation: tab.index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
