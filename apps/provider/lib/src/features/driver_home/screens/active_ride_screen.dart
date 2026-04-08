import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/ride_request_provider.dart';

/// Active ride screen — drives the four states from accepting a request all
/// the way through to ride completion.
///
/// Figma: nodes 195:11007 (en-route to pickup), 208:11210, 208:11599
/// PRD Reference: PRD 5.2
///
/// State machine:
///   - accepted / driverEnRoute   → full map + navigation header.
///       After ~6 seconds (proximity simulator) the bottom panel slides up
///       offering "ARRIVED AT DESTINATION".
///   - arrived                    → bottom panel stays up; primary action
///       becomes "START TRIP".
///   - inProgress                 → primary action becomes "END TRIP".
///   - completed                  → screen closes.
class ActiveRideScreen extends ConsumerStatefulWidget {
  const ActiveRideScreen({super.key});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// Time before the bottom panel auto-presents itself, simulating the
  /// driver getting close to the pickup pin.
  static const _proximityDelay = Duration(seconds: 6);
  static const _previewSize = 0.55;

  Timer? _proximityTimer;

  @override
  void initState() {
    super.initState();
    _proximityTimer = Timer(_proximityDelay, () {
      if (!mounted) return;
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          _previewSize,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _proximityTimer?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  void _handlePrimaryAction(Ride ride) {
    final notifier = ref.read(activeRideProvider.notifier);
    switch (ride.status) {
      case RideStatus.accepted:
      case RideStatus.driverEnRoute:
        notifier.markArrived();
      case RideStatus.arrived:
        notifier.startTrip();
      case RideStatus.inProgress:
        notifier.completeTrip();
        Navigator.of(context).pop('completed');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(activeRideProvider);
    if (ride == null) {
      return const Scaffold(
        body: Center(child: Text('No active ride')),
      );
    }

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: Stack(
        children: [
          // ── Full-screen map background ──
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(ride.pickupLat, ride.pickupLng),
                zoom: 15,
              ),
              onMapCreated: (c) {
                if (!_mapController.isCompleted) _mapController.complete(c);
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 100,
              ),
            ),
          ),

          // ── Navigation header (always visible) ──
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _NavigationHeader(),
          ),

          // ── Map controls: recenter + SOS ──
          Positioned(
            right: MyShopSpacing.md,
            top: MediaQuery.of(context).padding.top + 130,
            child: Column(
              children: [
                _MapControlButton(
                  icon: Icons.refresh,
                  onTap: () {},
                ),
                const SizedBox(height: MyShopSpacing.sm),
                _SosButton(onTap: () {}),
              ],
            ),
          ),

          // ── Bottom passenger panel (draggable sheet) ──
          // While the driver is en-route, the sheet sits fully off-screen
          // (`minChildSize == 0`). When proximity fires we animate it up to
          // its preview size; the driver can drag it further to expand,
          // collapse it back, or pull it down to peek the map.
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0,
            minChildSize: 0,
            maxChildSize: 0.78,
            snap: true,
            snapSizes: const [0, 0.55, 0.78],
            builder: (context, scrollController) {
              return _PassengerPanel(
                ride: ride,
                scrollController: scrollController,
                onPrimaryAction: () => _handlePrimaryAction(ride),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Navigation header ──────────────────────────────────────────────────────

class _NavigationHeader extends StatelessWidget {
  const _NavigationHeader();

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + 12,
        left: MyShopSpacing.md,
        right: MyShopSpacing.md,
      ),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: MyShopSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.navigation,
                  size: 22, color: MyShopColors.darkSlate),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('450m',
                      style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: MyShopColors.textPrimary)),
                  Text('Turn right onto Independence Ave',
                      style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 12,
                          color: MyShopColors.textSecondary),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 36,
              color: MyShopColors.divider,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('ETA',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.primaryGold,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                const Text('12 min',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.textPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Map controls ───────────────────────────────────────────────────────────

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: MyShopColors.darkSlate),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: MyShopColors.error,
          shape: BoxShape.circle,
          border: Border.all(color: MyShopColors.surfaceWhite, width: 3),
          boxShadow: [
            BoxShadow(
              color: MyShopColors.error.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 16, color: Colors.white),
            Text('SOS',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─── Passenger panel ────────────────────────────────────────────────────────

class _PassengerPanel extends StatelessWidget {
  const _PassengerPanel({
    required this.ride,
    required this.scrollController,
    required this.onPrimaryAction,
  });

  final Ride ride;
  final ScrollController scrollController;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 30,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              MyShopSpacing.md, 12, MyShopSpacing.md, MyShopSpacing.md),
          children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: MyShopColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.md),

              // Passenger row: avatar / name+rating / chat / phone
              Row(
                children: [
                  Stack(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0xFFFCEAE1),
                        child: Icon(Icons.person,
                            size: 28, color: MyShopColors.textSecondary),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: MyShopColors.online,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: MyShopColors.surfaceWhite, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.clientName ?? 'Passenger',
                          style: const TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: MyShopColors.primaryGoldLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star,
                                  size: 12, color: MyShopColors.ratingStar),
                              const SizedBox(width: 3),
                              Text(
                                '${ride.clientRating ?? 4.9}',
                                style: const TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: MyShopColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ContactButton(
                    icon: Icons.chat_bubble_outline,
                    filled: true,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _ContactButton(
                    icon: Icons.phone,
                    filled: false,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // Trip stepper
              _TripStepper(status: ride.status),
              const SizedBox(height: MyShopSpacing.md),

              // Pickup → Destination card with FARE
              Container(
                padding: const EdgeInsets.all(MyShopSpacing.md),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoutePoint(
                      colorRing: MyShopColors.darkSlate,
                      label: 'PICKUP POINT',
                      address: ride.pickupAddress,
                    ),
                    Container(
                      width: 1.5,
                      height: 14,
                      margin: const EdgeInsets.only(left: 9, top: 2, bottom: 2),
                      child: const _DottedVerticalLine(),
                    ),
                    _RoutePoint(
                      colorRing: MyShopColors.primaryGold,
                      label: 'DESTINATION',
                      address: ride.dropoffAddress,
                    ),
                    const SizedBox(height: 12),
                    const Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: MyShopColors.divider),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FARE',
                            style: TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: MyShopColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ride.estimatedFareDisplay,
                            style: const TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: MyShopColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MyShopSpacing.md),

              // Primary action button
              ElevatedButton(
                onPressed: onPrimaryAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.darkSlate,
                  foregroundColor: MyShopColors.textOnPrimary,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(40)),
                  textStyle: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5),
                  elevation: 4,
                  shadowColor: MyShopColors.darkSlate.withValues(alpha: 0.4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_primaryActionLabel(ride.status)),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, size: 22),
                  ],
                ),
              ),
              const SizedBox(height: MyShopSpacing.sm),

              // Helper caption
              Text(
                _helperCaption(ride.status),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _primaryActionLabel(RideStatus status) {
    return switch (status) {
      RideStatus.accepted ||
      RideStatus.driverEnRoute =>
        'ARRIVED AT DESTINATION',
      RideStatus.arrived => 'START TRIP',
      RideStatus.inProgress => 'END TRIP',
      _ => 'CONTINUE',
    };
  }

  String _helperCaption(RideStatus status) {
    return switch (status) {
      RideStatus.accepted ||
      RideStatus.driverEnRoute =>
        'TAP ARRIVED WHEN YOU REACH THE PIN',
      RideStatus.arrived => 'TAP START WHEN PASSENGER IS IN THE VEHICLE',
      RideStatus.inProgress => 'TAP END WHEN PASSENGER HAS EXITED SAFELY',
      _ => '',
    };
  }
}

// ─── Contact buttons (chat / phone) ─────────────────────────────────────────

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled ? MyShopColors.darkSlate : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: MyShopColors.divider),
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled ? MyShopColors.textOnPrimary : MyShopColors.darkSlate,
        ),
      ),
    );
  }
}

// ─── Trip stepper ───────────────────────────────────────────────────────────

class _TripStepper extends StatelessWidget {
  const _TripStepper({required this.status});
  final RideStatus status;

  int get _activeStep {
    return switch (status) {
      RideStatus.accepted || RideStatus.driverEnRoute => 0,
      RideStatus.arrived || RideStatus.inProgress => 1,
      RideStatus.completed => 2,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    const steps = [
      (label: 'PICKUP', icon: Icons.check),
      (label: 'ON TRIP', icon: Icons.navigation),
      (label: 'ARRIVAL', icon: Icons.location_on_outlined),
    ];

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _StepNode(
            icon: steps[i].icon,
            label: steps[i].label,
            isActive: i == _activeStep,
            isComplete: i < _activeStep,
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.only(bottom: 22),
                color: i < _activeStep
                    ? MyShopColors.primaryGold
                    : MyShopColors.divider,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isComplete,
  });
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final highlight = isActive || isComplete;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: highlight ? MyShopColors.primaryGold : MyShopColors.surfaceGrey,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: highlight ? Colors.white : MyShopColors.disabled,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color:
                highlight ? MyShopColors.textPrimary : MyShopColors.disabled,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

// ─── Route point row ────────────────────────────────────────────────────────

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({
    required this.colorRing,
    required this.label,
    required this.address,
  });

  final Color colorRing;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite,
            shape: BoxShape.circle,
            border: Border.all(color: colorRing, width: 2),
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colorRing,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DottedVerticalLine extends StatelessWidget {
  const _DottedVerticalLine();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(
        4,
        (_) => Container(
          width: 1.5,
          height: 2,
          color: MyShopColors.divider,
        ),
      ),
    );
  }
}
