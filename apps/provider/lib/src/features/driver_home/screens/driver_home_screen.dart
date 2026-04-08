import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/driver_status_provider.dart';
import '../providers/ride_request_provider.dart';
import '../screens/ride_request_screen.dart';
import '../widgets/auto_accept_card.dart';
import '../widgets/driver_home_header.dart';
import '../widgets/earnings_summary_section.dart';
import '../widgets/quick_operations_grid.dart';
import '../widgets/recent_activity_section.dart';
import '../widgets/online_offline_toggle.dart';

/// Driver Home Screen — Map-first view with draggable bottom sheet.
///
/// PRD Reference: PRD 5.2
/// Layout (top to bottom):
///   1. Full-screen Google Map background
///   2. Frosted-glass top header (hamburger, welcome text, avatar)
///   3. Trending-up FAB on map
///   4. Draggable bottom sheet containing:
///      - Online/Offline segmented toggle
///      - Today's Earnings + stats (Trips, Hours, Tips)
///      - Auto-accept Requests toggle
///      - Quick Operations 2×2 grid
///      - Recent Activity list
///   6. Bottom navigation bar (Home, Earnings, Trips, Account)
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final Completer<GoogleMapController> _mapController = Completer();

  // Kumasi, Ashanti Region — default centre for pilot city
  static const _kumasiCenter = LatLng(6.6885, -1.6244);

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(driverStatusProvider);

    return Scaffold(
      body: Stack(
        children: [
          // ── 1. Full-screen Google Map ──
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _kumasiCenter,
                zoom: 15,
              ),
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
              },
              myLocationEnabled: status.isOnline || status.isBusy,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
            ),
          ),

          // ── 2. Frosted-glass header ──
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DriverHomeHeader(),
          ),

          // ── 3. Trending-up FAB ──
          Positioned(
            top: 151,
            right: MyShopSpacing.md,
            child: _TrendingUpButton(
              onTap: () {
                // Dev preview: open the incoming ride request modal.
                final ride = ref.read(incomingRideRequestProvider);
                if (ride != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => RideRequestScreen(ride: ride),
                    ),
                  );
                }
              },
            ),
          ),

          // ── 4. Draggable bottom sheet ──
          DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.15,
            maxChildSize: 0.85,
            snap: true,
            snapSizes: const [0.15, 0.55, 0.85],
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 30,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 13),
                        width: 48,
                        height: 6,
                        decoration: BoxDecoration(
                          color: MyShopColors.surfaceGrey.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),

                    // Online/Offline toggle
                    const OnlineOfflineToggle(),

                    // Earnings summary
                    const EarningsSummarySection(),

                    // Auto-accept toggle
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                      child: AutoAcceptCard(),
                    ),

                    const SizedBox(height: MyShopSpacing.lg),

                    // Quick Operations
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                      child: QuickOperationsGrid(),
                    ),

                    const SizedBox(height: MyShopSpacing.lg),

                    // Recent Activity
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                      child: RecentActivitySection(),
                    ),

                    const SizedBox(height: MyShopSpacing.xxl),
                  ],
                ),
              );
            },
          ),
        ],
      ),

      // Bottom nav provided by ShellRoute in router.dart
    );
  }
}

/// Circular button with trending-up icon (from Figma).
class _TrendingUpButton extends StatelessWidget {
  const _TrendingUpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          shape: BoxShape.circle,
          border: Border.all(
            color: MyShopColors.divider.withValues(alpha: 0.5),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x21171A1F),
              blurRadius: 7,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Color(0x14171A1F),
              blurRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.trending_up,
          color: MyShopColors.textPrimary,
          size: 24,
        ),
      ),
    );
  }
}
