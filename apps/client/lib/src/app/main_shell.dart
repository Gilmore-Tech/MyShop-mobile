import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ride/providers/ride_provider.dart';
import 'router.dart';
import 'widgets/app_bottom_nav.dart';

/// Persistent shell that wraps the four main tabs.
/// Renders the current branch body via [navigationShell] and shows
/// the shared [AppBottomNav] that survives tab switches.
///
/// Also responsible for resuming a force-quit / crashed mid-trip ride:
/// the recovery bridge in `core/providers/active_ride_recovery_bridge.dart`
/// hydrates `bookingPhase`/`matchedDriver` after fetching the rider's
/// in-flight ride from REST; this widget listens for that hydration and
/// navigates to `/ride/tracking` so the rider lands back on the live map.
class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resume mid-trip rides on cold start. Fires when the recovery bridge
    // pushes `bookingPhase = accepted` after finding an in-flight ride for
    // the rider. Skipped if the user is already on the tracking branch
    // (avoids stacking the screen on a redundant accepted-state event from
    // the live flow).
    ref.listen<BookingPhase>(bookingPhaseProvider, (prev, next) {
      if (next != BookingPhase.accepted) return;
      // The recovery bridge always sets `matchedDriverProvider` before
      // flipping `bookingPhase`, so reading it here is safe.
      final driver = ref.read(matchedDriverProvider);
      if (driver == null) return;
      final currentLocation = GoRouterState.of(context).matchedLocation;
      if (currentLocation.startsWith(AppRoutes.rideTracking)) return;
      // Don't override the live matching → tracking flow either; the
      // matching screen pushes the route itself.
      if (currentLocation == AppRoutes.rideMatching) return;
      context.go(AppRoutes.rideTracking, extra: driver);
    });

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
