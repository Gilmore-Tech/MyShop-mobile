import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';
import '../widgets/driver_info_card.dart';
import '../widgets/driver_radar.dart';

/// PRD 4.3 — Driver Matching Screen
/// Radar animation while finding nearby drivers.
/// Purely reactive: requestRideAndMatchDriver() is started by
/// FareEstimateScreen before navigating here. This screen watches
/// [bookingPhaseProvider] and [matchedDriverProvider] and navigates to
/// tracking once a driver is found, or shows a failure card if the
/// request fails / no drivers accept in time.
class DriverMatchingScreen extends ConsumerStatefulWidget {
  const DriverMatchingScreen({super.key});

  @override
  ConsumerState<DriverMatchingScreen> createState() =>
      _DriverMatchingScreenState();
}

class _DriverMatchingScreenState extends ConsumerState<DriverMatchingScreen> {
  @override
  Widget build(BuildContext context) {
    // Navigate to ride tracking 1.2 s after a driver is matched —
    // the brief pause lets the rider see the "Accepted" state before
    // the map opens.
    ref.listen<BookingPhase>(bookingPhaseProvider, (prev, next) {
      if (next == BookingPhase.driverFound) {
        final driver = ref.read(matchedDriverProvider);
        if (driver == null || !mounted) return;
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (!mounted) return;
          context.go(AppRoutes.rideTracking, extra: driver);
        });
      }
    });

    final phase = ref.watch(bookingPhaseProvider);
    final driver = ref.watch(matchedDriverProvider);
    final driversFound = phase == BookingPhase.driverFound;
    final failed = phase == BookingPhase.failed;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: failed
            ? const _FailureView()
            : Column(
                children: [
                  _TopBar(
                    driversFound: driversFound,
                    driversAvailable: driver?.driversAvailable ?? 0,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: DriverRadar(
                        driversFound: driversFound,
                        driversAvailable: driver?.driversAvailable ?? 0,
                      ),
                    ),
                  ),
                  if (!driversFound) const _SearchStatusBar(),
                  if (driversFound && driver != null)
                    DriverInfoCard(driver: driver),
                ],
              ),
      ),
    );
  }
}

// ── Failure view ──────────────────────────────────────────────────────────────

class _FailureView extends ConsumerWidget {
  const _FailureView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(bookingFailureMessageProvider) ??
        "We couldn't request your ride.";

    Future<void> dismiss() async {
      final container = ProviderScope.containerOf(context, listen: false);
      await cancelInFlightRideRequest(container);
      if (!context.mounted) return;
      context.go(AppRoutes.home);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: MyShopColors.textPrimary),
              onPressed: dismiss,
            ),
          ),
          const Spacer(),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: MyShopColors.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: MyShopColors.error,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No driver matched',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.4,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: dismiss,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.primaryGold,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Back to home'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool driversFound;
  final int driversAvailable;

  const _TopBar({required this.driversFound, required this.driversAvailable});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: driversFound
            ? _DriversAvailablePill(count: driversAvailable)
            : _SearchingBar(),
      ),
    );
  }
}

class _SearchingBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      key:    const ValueKey('searching'),
      height: h * 0.055,
      padding: EdgeInsets.symmetric(horizontal: w * 0.046),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(h * 0.027),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset:     const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: w * 0.044, color: MyShopColors.textSecondary),
          SizedBox(width: w * 0.021),
          Text(
            'Finding nearby drivers...',
            style: TextStyle(
              fontSize:   w * 0.036,
              fontWeight: FontWeight.w500,
              color:      MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriversAvailablePill extends StatelessWidget {
  final int count;
  const _DriversAvailablePill({required this.count});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      key: const ValueKey('found'),
      padding: EdgeInsets.symmetric(horizontal: w * 0.051, vertical: h * 0.012),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGold,
        borderRadius: BorderRadius.circular(h * 0.026),
        boxShadow: [
          BoxShadow(
            color: MyShopColors.primaryGold.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        '$count Drivers available',
        style: TextStyle(
          fontSize: w * 0.033,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Search status bar ─────────────────────────────────────────────────────────

class _SearchStatusBar extends ConsumerWidget {
  const _SearchStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(searchCountdownProvider);
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded,
              size: 20, color: MyShopColors.textSecondary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Search expires in',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const Text(
                'Looking in 2km radius',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '$mm:$ss',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: MyShopColors.primaryGold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
