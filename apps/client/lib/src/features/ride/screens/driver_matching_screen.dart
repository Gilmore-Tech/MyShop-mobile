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
  /// Guards against scheduling the navigation more than once when both the
  /// initState post-frame check and a later [ref.listen] transition both
  /// see `accepted` — `context.go` while the screen is mid-disposal causes
  /// a router assertion.
  bool _navigatedToTracking = false;

  @override
  void initState() {
    super.initState();
    // Catch the race where the driver acks acceptance during the navigation
    // transition from FareEstimate → Matching. By the time this screen runs
    // its first build, `bookingPhaseProvider` may already be `accepted` —
    // and `ref.listen` only fires on *subsequent* changes, so without this
    // sync check the rider would be stranded on the matching radar with no
    // further state transitions to react to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(bookingPhaseProvider) == BookingPhase.accepted) {
        _goToTracking();
      }
    });
  }

  void _goToTracking() {
    if (_navigatedToTracking || !mounted) return;
    final driver = ref.read(matchedDriverProvider);
    if (driver == null) return;
    _navigatedToTracking = true;
    context.go(AppRoutes.rideTracking, extra: driver);
  }

  @override
  Widget build(BuildContext context) {
    // Navigate to ride tracking the moment the driver acks acceptance. We
    // used to add a 1.2s "let the rider see the Accepted state" pause, but
    // the radar keeps animating at 60fps during that window AND the
    // tracking screen's Mapbox init runs on top — on slower Android
    // devices that combo would push past the 5s ANR threshold and the OS
    // would show "myshop_client isn't responding". Navigating immediately
    // gives Mapbox the headroom it needs.
    ref.listen<BookingPhase>(bookingPhaseProvider, (prev, next) {
      if (next == BookingPhase.accepted) _goToTracking();
    });

    final phase = ref.watch(bookingPhaseProvider);
    final driver = ref.watch(matchedDriverProvider);
    final notifiedCount = ref.watch(driversNotifiedProvider);
    // Only render the "matched" radar (with car decorations + matched-pill)
    // once we have a confirmed accept. `driverFound` is a notified-but-not-
    // confirmed state and gets its own copy in [_TopBar] / [_SearchStatusBar]
    // so we don't lie to the rider with "0 Drivers available".
    final accepted = phase == BookingPhase.accepted;
    final driversFound = accepted;
    final failed = phase == BookingPhase.failed;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: failed
            ? const _FailureView()
            : Column(
                children: [
                  _TopBar(
                    phase: phase,
                    notifiedCount: notifiedCount,
                    matchedCount: driver?.driversAvailable ?? 0,
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
  final BookingPhase phase;
  final int notifiedCount;
  final int matchedCount;

  const _TopBar({
    required this.phase,
    required this.notifiedCount,
    required this.matchedCount,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (phase) {
      BookingPhase.accepted => _DriversAvailablePill(
          count: matchedCount, key: const ValueKey('found')),
      BookingPhase.driverFound =>
        _NotifyingPill(count: notifiedCount, key: const ValueKey('notifying')),
      _ => _SearchingBar(),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: child,
      ),
    );
  }
}

class _SearchingBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final progress = ref.watch(matcherProgressProvider);
    final label = _searchLabel(progress);
    return Container(
      key: const ValueKey('searching'),
      height: h * 0.055,
      padding: EdgeInsets.symmetric(horizontal: w * 0.046),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(h * 0.027),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded,
              size: w * 0.044, color: MyShopColors.textSecondary),
          SizedBox(width: w * 0.021),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Copy is driven by `ride:matcher_progress` from the backend so the rider
  /// sees what the matcher is actually doing instead of a frozen spinner.
  /// First attempt: "Finding nearby drivers". Later attempts: either
  /// "Expanding search to N km" (matcher just widened the radius) or
  /// "Trying another driver" (decline-triggered retry at same radius).
  static String _searchLabel(MatcherProgress? progress) {
    if (progress == null || progress.attempt <= 1) {
      return 'Finding nearby drivers…';
    }
    if (progress.driversRemaining == 0) {
      return 'Still searching nearby…';
    }
    if (progress.radiusKm > 0) {
      final km = progress.radiusKm.toStringAsFixed(
        progress.radiusKm == progress.radiusKm.roundToDouble() ? 0 : 1,
      );
      return 'Expanding search to $km km…';
    }
    return 'Trying another driver…';
  }
}

class _DriversAvailablePill extends StatelessWidget {
  final int count;
  const _DriversAvailablePill({required this.count, super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final label = count == 1 ? 'Driver matched' : '$count Drivers matched';
    return Container(
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
        label,
        style: TextStyle(
          fontSize: w * 0.033,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Pill shown while the matcher has notified drivers and we're waiting for
/// one to tap Accept. Distinct from [_DriversAvailablePill] (post-accept)
/// so the rider doesn't see "0 Drivers available" before a driver acks.
class _NotifyingPill extends StatelessWidget {
  final int count;
  const _NotifyingPill({required this.count, super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final label =
        count == 1 ? 'Notifying 1 driver...' : 'Notifying $count drivers...';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.051, vertical: h * 0.012),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(h * 0.026),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: w * 0.038,
            height: w * 0.038,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(MyShopColors.primaryGold),
            ),
          ),
          SizedBox(width: w * 0.025),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
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
