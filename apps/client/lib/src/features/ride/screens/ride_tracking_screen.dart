import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';
import '../widgets/ride_route_map.dart';
import '../widgets/ride_tracking_sheet.dart';

// Design tokens
const _error = Color(0xFFEB5757);

/// PRD 4.6 — Ride Tracking Screen
///
/// Full-screen map behind a draggable bottom sheet. The rider sees the live
/// route + ETA at any time; pulling the sheet up reveals ride details and the
/// cancel request action, pulling it down maximises the map.
class RideTrackingScreen extends ConsumerStatefulWidget {
  final MatchedDriver driver;
  final String destination;

  const RideTrackingScreen({
    super.key,
    required this.driver,
    this.destination = 'Kumasi City Mall, Lake Road',
  });

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen> {
  static const double _initialSheetSize = 0.52;
  static const double _minSheetSize = 0.28;
  static const double _maxSheetSize = 0.9;

  // Dev-friendly cadences so we can watch each transition happen in seconds
  // rather than minutes. Swap to 60s once backend pushes real lifecycle events.
  static const Duration _etaTickInterval = Duration(seconds: 10);
  static const Duration _tripTickInterval = Duration(seconds: 10);

  // How long the driver "waits" at pickup before auto-starting the trip in dev.
  static const Duration _autoStartTripAfter = Duration(seconds: 15);

  final _sheetController = DraggableScrollableController();
  Timer? _etaTimer;
  Timer? _waitingTimer;
  Timer? _tripTimer;
  double _sheetSize = _initialSheetSize;

  @override
  void initState() {
    super.initState();
    // Reset ride-tracking state on fresh entry
    ref.read(rideEtaProvider.notifier).setEta(4);
    ref.read(tripEtaProvider.notifier).setEta(12);
    ref.read(waitingCountdownProvider.notifier).reset();
    ref.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.enRoute;

    _startEtaTicker();
    _sheetController.addListener(_handleSheetChange);
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    _waitingTimer?.cancel();
    _tripTimer?.cancel();
    _sheetController.removeListener(_handleSheetChange);
    _sheetController.dispose();
    super.dispose();
  }

  void _startEtaTicker() {
    _etaTimer = Timer.periodic(_etaTickInterval, (_) {
      if (!mounted) return;
      final notifier = ref.read(rideEtaProvider.notifier);
      notifier.decrement();
      if (ref.read(rideEtaProvider) == 0) {
        _onDriverArrived();
      }
    });
  }

  void _onDriverArrived() {
    _etaTimer?.cancel();
    ref.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.arrived;
    // Tick once per second — keeps going into negative values once the free
    // wait is up so the sheet can surface the overtime surcharge.
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      ref.read(waitingCountdownProvider.notifier).tick();
    });
    // Auto-start the trip after a short grace period (dev simulation of the
    // driver tapping "Start Trip" once the rider is in the car).
    Future.delayed(_autoStartTripAfter, () {
      if (!mounted) return;
      if (ref.read(rideTrackingPhaseProvider) == RideTrackingPhase.arrived) {
        _onTripStart();
      }
    });
  }

  void _onTripStart() {
    _waitingTimer?.cancel();
    ref.read(rideTrackingPhaseProvider.notifier).state =
        RideTrackingPhase.inProgress;
    _tripTimer = Timer.periodic(_tripTickInterval, (_) {
      if (!mounted) return;
      ref.read(tripEtaProvider.notifier).decrement();
      if (ref.read(tripEtaProvider) == 0) {
        _onTripComplete();
      }
    });
  }

  void _onTripComplete() {
    _tripTimer?.cancel();
    if (!mounted) return;
    context.go(AppRoutes.rideComplete);
  }

  void _handleSheetChange() {
    if (!_sheetController.isAttached || !mounted) return;
    setState(() => _sheetSize = _sheetController.size);
  }

  void _onCancel() {
    // TODO: send cancel to backend, then return to home.
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(rideTrackingPhaseProvider);
    final pickupEta = ref.watch(rideEtaProvider);
    final tripEta = ref.watch(tripEtaProvider);
    final waitingSeconds =
        phase == RideTrackingPhase.arrived ? ref.watch(waitingCountdownProvider) : null;
    final mapEta =
        phase == RideTrackingPhase.inProgress ? tripEta : pickupEta;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sosBottom = screenHeight * _sheetSize + 14;

    return Scaffold(
      backgroundColor: const Color(0xFFEDEDE6),
      body: Stack(
        children: [
          Positioned.fill(
            child: RideRouteMap(
              destination: widget.destination,
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
          color: _error,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _error.withValues(alpha: 0.45),
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
            color: Color(0xFF161A1D),
          ),
        ),
        content: const Text(
          'Are you in danger? We will call Ghana Police Service (191) and share your location.',
          style: TextStyle(color: Color(0xFF555E68)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF555E68)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: url_launcher → tel:191 + send location to backend
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _error,
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
