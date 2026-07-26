import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../home/providers/home_provider.dart';
import '../data/ride_cancellation_coordinator.dart';
import '../providers/ride_payment_method_provider.dart';
import '../providers/ride_provider.dart';
import '../providers/ride_search_provider.dart';
import '../widgets/ride_route_map.dart';
import '../widgets/ride_tracking_sheet.dart';

/// PRD 4.6 — Ride Tracking Screen
///
/// Full-screen map behind a draggable bottom sheet. The rider sees the live
/// route + ETA at any time; pulling the sheet up reveals ride details and the
/// cancel request action, pulling it down maximises the map.
class RideTrackingScreen extends ConsumerStatefulWidget {
  final MatchedDriver driver;

  const RideTrackingScreen({
    super.key,
    required this.driver,
  });

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen> {
  static const double _initialSheetSize = 0.52;
  static const double _minSheetSize = 0.28;
  static const double _maxSheetSize = 0.9;

  final _sheetController = DraggableScrollableController();

  /// Real wall-clock counter for how long the rider has been waiting at
  /// pickup. Started when the driver reports `arrived`, cancelled when the
  /// trip starts. Goes negative once the free-wait window is exhausted so
  /// the sheet can surface the overtime surcharge.
  Timer? _waitingTimer;
  double _sheetSize = _initialSheetSize;

  @override
  void initState() {
    super.initState();
    // Seed the ETA values from whatever the backend gave us via the matched
    // driver payload. These don't tick down on the client any more —
    // `ride:state` snapshots from the driver advance the phase; if the
    // backend pushes refreshed ETAs in the future, drop them straight into
    // these providers from socket_provider.dart.
    //
    // Deferred to a microtask: when this screen is pushed via `context.go`
    // from a post-frame callback (e.g. the matching screen's already-
    // accepted check), `initState` runs while the widget tree is still
    // building, and Riverpod's StateNotifier guard refuses synchronous
    // provider mutations there. Microtask runs after build completes.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(rideEtaProvider.notifier).setEta(widget.driver.minutesAway);
      ref.read(tripEtaProvider.notifier).setEta(widget.driver.minutesAway);
      ref.read(waitingCountdownProvider.notifier).reset();
      ref.read(rideTrackingPhaseProvider.notifier).state =
          RideTrackingPhase.enRoute;
    });

    _sheetController.addListener(_handleSheetChange);
  }

  @override
  void dispose() {
    _waitingTimer?.cancel();
    _sheetController.removeListener(_handleSheetChange);
    _sheetController.dispose();
    super.dispose();
  }

  void _onArrived() {
    _waitingTimer?.cancel();
    // Reset on entry so a previous arrival's elapsed time doesn't carry over.
    ref
        .read(waitingCountdownProvider.notifier)
        .resetFromArrival(ref.read(rideArrivalAnchorProvider));
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      ref.read(waitingCountdownProvider.notifier).tick();
    });
  }

  void _onTripStarted() {
    _waitingTimer?.cancel();
  }

  void _handleSheetChange() {
    if (!_sheetController.isAttached || !mounted) return;
    setState(() => _sheetSize = _sheetController.size);
  }

  /// Double-tap guard so a slow API response doesn't queue a second
  /// cancel request while the first is in flight.
  bool _cancellingNow = false;

  Future<void> _onCancel() async {
    if (_cancellingNow) {
      developer.log('[CANCEL] re-entry blocked — already cancelling',
          name: 'RideTrackingScreen');
      return;
    }
    final rideId = ref.read(activeRideIdProvider);
    developer.log('[CANCEL] tapped — rideId=$rideId',
        name: 'RideTrackingScreen');
    if (rideId == null || rideId.isEmpty) {
      // No active ride to cancel — just bail out to home.
      developer.log('[CANCEL] no active rideId, navigating home',
          name: 'RideTrackingScreen');
      if (mounted) context.go(AppRoutes.home);
      return;
    }
    final phase = ref.read(rideTrackingPhaseProvider);
    if (phase != RideTrackingPhase.enRoute &&
        phase != RideTrackingPhase.arrived) {
      developer.log('[CANCEL] blocked for phase=$phase',
          name: 'RideTrackingScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This trip has already started. Please use Help or contact support.',
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          'Are you sure you want to cancel this ride?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      developer.log('[CANCEL] dialog dismissed without confirmation',
          name: 'RideTrackingScreen');
      return;
    }
    final phaseAfterConfirm = ref.read(rideTrackingPhaseProvider);
    if (phaseAfterConfirm != RideTrackingPhase.enRoute &&
        phaseAfterConfirm != RideTrackingPhase.arrived) {
      developer.log(
          '[CANCEL] blocked after confirmation for phase=$phaseAfterConfirm',
          name: 'RideTrackingScreen');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This trip has already started. Please use Help or contact support.',
          ),
        ),
      );
      return;
    }

    _cancellingNow = true;
    final messenger = ScaffoldMessenger.of(context);
    developer.log('[CANCEL] PATCH /rides/$rideId/cancel',
        name: 'RideTrackingScreen');
    final cancellation = await cancelRideWithAuthority(
      rideService: ref.read(rideServiceProvider),
      rideId: rideId,
      reason: 'rider_cancelled',
    );
    if (!cancellation.confirmedCancelled) {
      developer.log(
        '[CANCEL] not confirmed; local ride preserved '
        '(reconciled=${cancellation.reconciled})',
        name: 'RideTrackingScreen',
        level: 900,
      );
      _cancellingNow = false;
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(cancellation.message)));
      }
      return;
    }

    await ref.read(rideBookingAttemptStoreProvider).clear();
    ref.invalidate(homeRecentActivityProvider);
    final result = cancellation.response;
    final feePesewas = (result['cancellationFeePesewas'] as num?)?.toInt() ?? 0;
    var message = cancellation.message;
    if (result['cancellationConsequencesApplied'] == false) {
      message = result['notice'] as String? ??
          'Ride cancelled. Automatic fees and penalties are temporarily paused.';
    } else if (feePesewas > 0) {
      final fee = (feePesewas / 100).toStringAsFixed(2);
      message = 'Ride cancelled. Cancellation fee: GHS $fee';
    }
    developer.log(
      '[CANCEL] confirmed — fee=${feePesewas}p '
      'reconciled=${cancellation.reconciled}',
      name: 'RideTrackingScreen',
    );

    // Reset only after authoritative cancellation so a network/server failure
    // cannot hide a ride that remains active on the backend.
    // Reset every ride-related provider so the next booking starts
    // from a clean slate. The original cancel handler missed
    // rideTrackingPhaseProvider + liveDriverPositionProvider, which
    // could leave a stale phase / marker if the user navigated back
    // to the tracking surface before the next ride loaded.
    ref.read(activeRideIdProvider.notifier).state = null;
    ref.read(matchedDriverProvider.notifier).state = null;
    ref.read(bookingPhaseProvider.notifier).reset();
    ref.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.enRoute;
    ref.read(liveDriverPositionProvider.notifier).state = null;
    ref.read(rideMatchedViaSocketProvider.notifier).state = false;
    ref.read(rideArrivalAnchorProvider.notifier).state = null;

    if (!mounted) {
      _cancellingNow = false;
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    context.go(AppRoutes.home);
    _cancellingNow = false;
  }

  @override
  Widget build(BuildContext context) {
    // Self-healing belt: re-emits `client:track:ride` and periodically
    // hydrates from REST so a dropped socket / room-join race during the
    // ride doesn't leave the rider stuck on a stale phase. Auto-disposes
    // when this screen unmounts.
    ref.watch(activeRideTrackingMaintainerProvider);

    // React to phase transitions pushed in by `ride:state` socket events.
    // The driver app is the source of truth for ride lifecycle: when they
    // tap "Arrived" / "Start Trip" / "End Trip", the backend broadcasts a
    // fresh `ride:state` snapshot to the rider's room and socket_provider
    // flips rideTrackingPhaseProvider — this listener turns those flips
    // into the matching local side-effects (waiting timer, navigation).
    ref.listen<RideTrackingPhase>(rideTrackingPhaseProvider, (prev, next) {
      if (prev == next) return;
      switch (next) {
        case RideTrackingPhase.enRoute:
          _waitingTimer?.cancel();
        case RideTrackingPhase.arrived:
          _onArrived();
        case RideTrackingPhase.inProgress:
          _onTripStarted();
        case RideTrackingPhase.completed:
          _waitingTimer?.cancel();
          ref.read(rideArrivalAnchorProvider.notifier).state = null;
          if (!mounted) return;
          // Route in-app payments through /ride/:id/payment to settle the
          // Paystack charge before the rate sheet + receipt. Cash trips
          // skip straight to /ride/complete since there's nothing to
          // charge — the driver collects in person.
          final receipt = ref.read(rideReceiptProvider);
          final method = ridePaymentMethodFromWire(receipt?.paymentMethod);
          final rideId = ref.read(activeRideIdProvider);
          if (method != null && method.isInApp && rideId != null) {
            context.go(AppRoutes.ridePaymentPath(rideId));
          } else {
            context.go(AppRoutes.rideComplete);
          }
        case RideTrackingPhase.cancelled:
          // Driver (or system) cancelled mid-trip. Tell the rider, wipe
          // local ride state so the next booking starts fresh, and route
          // back to home. The bookingFailureMessageProvider was set by
          // socket_provider with the role-aware reason ("The driver
          // cancelled this ride." / "We couldn't find a driver…").
          _waitingTimer?.cancel();
          if (!mounted) return;
          final reason = ref.read(bookingFailureMessageProvider) ??
              'This ride was cancelled.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(reason)),
          );
          ref.read(activeRideIdProvider.notifier).state = null;
          ref.read(matchedDriverProvider.notifier).state = null;
          ref.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.enRoute; // reset for next ride
          ref.read(rideArrivalAnchorProvider.notifier).state = null;
          ref.read(bookingPhaseProvider.notifier).reset();
          context.go(AppRoutes.home);
      }
    });

    // Fast ride:status and full ride:state can arrive in either order. If the
    // server arrival timestamp is learned after the phase has already flipped
    // to arrived, realign the countdown so rider and driver timers match.
    ref.listen<DateTime?>(rideArrivalAnchorProvider, (prev, next) {
      if (prev == next) return;
      if (ref.read(rideTrackingPhaseProvider) != RideTrackingPhase.arrived) {
        return;
      }
      ref.read(waitingCountdownProvider.notifier).resetFromArrival(next);
    });

    final phase = ref.watch(rideTrackingPhaseProvider);
    final pickupEta = ref.watch(rideEtaProvider);
    final tripEta = ref.watch(tripEtaProvider);
    final waitingSeconds = phase == RideTrackingPhase.arrived
        ? ref.watch(waitingCountdownProvider)
        : null;
    final mapEta = phase == RideTrackingPhase.inProgress ? tripEta : pickupEta;
    final search = ref.watch(rideSearchProvider);
    final destinationLabel = search.destination?.name ?? 'Your destination';
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sosBottom = screenHeight * _sheetSize + 14;

    return Scaffold(
      backgroundColor: const Color(0xFFEDEDE6),
      body: Stack(
        children: [
          Positioned.fill(
            child: RideRouteMap(
              destination: destinationLabel,
              etaMinutes: mapEta,
              phase: phase,
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _initialSheetSize,
            minChildSize: _minSheetSize,
            maxChildSize: _maxSheetSize,
            snap: true,
            snapSizes: const [_minSheetSize, _initialSheetSize, _maxSheetSize],
            builder: (_, scrollController) => RideTrackingSheet(
              driver: widget.driver,
              scrollController: scrollController,
              onCancel: _onCancel,
              waitingSeconds: waitingSeconds,
              isInProgress: phase == RideTrackingPhase.inProgress,
              // Only show Cancel Request while a cancel is still
              // semantically meaningful — driver en-route to pickup
              // or waiting at pickup. After trip start / completion /
              // cancellation the button hides immediately.
              canCancel: phase == RideTrackingPhase.enRoute ||
                  phase == RideTrackingPhase.arrived,
            ),
          ),
          Positioned(
            right: 16,
            bottom: sosBottom,
            child: const _SosButton(),
          ),
        ],
      ),
    );
  }
}

// ── SOS button ────────────────────────────────────────────────────────────────

class _SosButton extends StatelessWidget {
  const _SosButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Every SOS entry uses the owner-approved three-second hold. Keeping a
      // separate tap+dialog implementation here made the safety gesture
      // inconsistent and could trigger an alert accidentally.
      onTap: () => context.push(AppRoutes.safetyEmergency),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: MyShopColors.error,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: MyShopColors.error.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'SOS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
