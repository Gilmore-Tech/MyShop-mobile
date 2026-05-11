import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
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
    ref.read(waitingCountdownProvider.notifier).reset();
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

  Future<void> _onCancel() async {
    final rideId = ref.read(activeRideIdProvider);
    if (rideId == null || rideId.isEmpty) {
      // No active ride to cancel — just bail out to home.
      if (mounted) context.go(AppRoutes.home);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          'Cancelling within 3 minutes of the driver accepting is free. '
          'After that a small cancellation fee applies.',
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
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    String message = 'Ride cancelled.';
    try {
      final result = await ref.read(rideServiceProvider).cancelRide(
            rideId,
            reason: 'rider_cancelled',
          );
      final feePesewas = (result['cancellationFeePesewas'] as num?)?.toInt() ?? 0;
      if (feePesewas > 0) {
        final fee = (feePesewas / 100).toStringAsFixed(2);
        message = 'Ride cancelled. Cancellation fee: GHS $fee';
      }
    } on ApiException catch (e) {
      message = e.message;
    } catch (_) {
      message = 'Could not cancel the ride. Please try again.';
    }

    // Reset local state regardless of the outcome — the rider's intent is
    // to abandon, and the backend (if it succeeded) has already broadcast.
    ref.read(activeRideIdProvider.notifier).state = null;
    ref.read(matchedDriverProvider.notifier).state = null;
    ref.read(bookingPhaseProvider.notifier).reset();

    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
    context.go(AppRoutes.home);
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
      }
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
              onAddStop: () => context.push(AppRoutes.rideStops),
              waitingSeconds: waitingSeconds,
              isInProgress: phase == RideTrackingPhase.inProgress,
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
      onTap: () => _showSosDialog(context),
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

  void _showSosDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Emergency',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        content: const Text(
          'Are you in danger? We will call Ghana Police Service (191) and share your location.',
          style: TextStyle(color: MyShopColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: MyShopColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: url_launcher → tel:191 + send location to backend
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Call 191'),
          ),
        ],
      ),
    );
  }
}
