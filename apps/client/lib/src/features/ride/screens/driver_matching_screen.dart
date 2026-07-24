import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/edit_trip_provider.dart';
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
      final cancelled = await cancelInFlightRideRequest(container);
      if (!context.mounted) return;
      if (!cancelled) {
        final failure = container.read(bookingFailureMessageProvider) ??
            "We couldn't confirm whether the ride was cancelled.";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure)),
        );
        return;
      }
      resetRideRequestDraft(container.read);
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
    final label = matcherStatusLabel(progress);
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
}

/// Single source of truth for the matching-screen status copy, used by both
/// the top pill and the bottom status bar so the rider gets a consistent
/// message. Copy maps directly to the backend's `reason` field:
///
///   initial → "Notifying N driver(s)…"
///   decline → "Driver declined — searching for another driver"  (fresh > 0)
///           → "Driver declined — expanding search to N km"      (fresh == 0)
///   timeout → "No response — expanding search to N km"
///
/// When fresh drivers were dispatched at the current radius, the radius
/// gets a "within N km" suffix so the rider sees the matcher actually
/// reaching further out.
String matcherStatusLabel(MatcherProgress? progress) {
  if (progress == null) return 'Looking for a driver nearby…';
  final radius = progress.radiusKm;
  final fresh = progress.driversRemaining;
  final km = radius > 0
      ? radius.toStringAsFixed(radius == radius.roundToDouble() ? 0 : 1)
      : null;

  switch (progress.reason) {
    case MatcherReason.initial:
      final n = fresh > 0 ? fresh : progress.driversTried;
      final pluralised = n == 1 ? '1 driver' : '$n drivers';
      return km != null
          ? 'Notifying $pluralised within $km km'
          : 'Notifying $pluralised nearby';
    case MatcherReason.decline:
      if (fresh > 0) {
        return km != null
            ? 'Driver declined — searching within $km km'
            : 'Driver declined — searching for another driver';
      }
      return km != null
          ? 'Driver declined — expanding search to $km km'
          : 'Driver declined — expanding search';
    case MatcherReason.timeout:
      if (fresh > 0) {
        return km != null
            ? 'No response — trying another driver within $km km'
            : 'No response — trying another driver';
      }
      return km != null
          ? 'Expanding search to $km km radius'
          : 'Expanding search to find a driver';
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

/// Bottom-of-screen status panel. The countdown was removed on 2026-05-13 —
/// it implied a hard deadline that didn't match the backend's actual budget
/// and made the screen feel frozen between status events. The panel now
/// shows the live matcher status driven by `ride:matcher_progress`, plus a
/// gentle animation so the rider still has a sense of activity.
class _SearchStatusBar extends ConsumerWidget {
  const _SearchStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(matcherProgressProvider);
    final headline = _headline(progress);
    final sub = matcherStatusLabel(progress);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(
                MyShopColors.primaryGold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Short, stable headline that doesn't churn on every event. The actual
  /// "what's happening right now" detail lives in the subtitle, which is
  /// `matcherStatusLabel(progress)`.
  static String _headline(MatcherProgress? progress) {
    if (progress == null) return 'Looking for a driver';
    switch (progress.reason) {
      case MatcherReason.initial:
        return 'Notifying drivers';
      case MatcherReason.decline:
        return 'Driver declined';
      case MatcherReason.timeout:
        return progress.driversRemaining > 0
            ? 'Trying another driver'
            : 'Expanding search';
    }
  }
}
