import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../data/road_snap_service.dart';
import '../providers/driver_location_provider.dart';
import '../providers/driver_status_provider.dart';
import '../providers/ride_request_provider.dart';
import '../screens/ride_request_screen.dart';
import '../widgets/auto_accept_card.dart';
import '../widgets/driver_car_marker.dart';
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

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
    with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();

  // Kumasi, Ashanti Region — fallback centre when location is unavailable.
  static const _kumasiCenter = LatLng(6.6885, -1.6244);

  BitmapDescriptor? _carIcon;
  Marker? _driverMarker;

  /// Animates the marker from the last rendered point to the next road-snapped
  /// GPS fix so the car appears to glide down the street rather than teleport
  /// on each update.
  late final AnimationController _moveController;

  LatLng? _fromPos;
  LatLng? _toPos;
  double _fromRotation = 0;
  double _toRotation = 0;
  LatLng? _currentPos;
  double _currentRotation = 0;

  /// Guards camera auto-follow so we only animate on the first location fix
  /// after each online session (we don't want to fight the user if they pan).
  bool _hasCenteredOnDriver = false;

  @override
  void initState() {
    super.initState();
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(_onAnimationTick);
    _loadCarIcon();
    _goToCurrentLocation();
  }

  @override
  void dispose() {
    _moveController
      ..removeListener(_onAnimationTick)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadCarIcon() async {
    final pixelRatio = WidgetsBinding.instance.platformDispatcher.views.first
        .devicePixelRatio;
    final icon = await DriverCarMarker.create(devicePixelRatio: pixelRatio);
    if (!mounted) return;
    setState(() => _carIcon = icon);
  }

  Future<void> _goToCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition();
    final controller = await _mapController.future;
    if (!mounted) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        15,
      ),
    );
  }

  /// Linearly interpolates between two headings along the short arc, so the
  /// car rotates the correct way when crossing 0°/360°.
  double _lerpAngle(double from, double to, double t) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t) % 360;
  }

  void _onAnimationTick() {
    final from = _fromPos;
    final to = _toPos;
    final icon = _carIcon;
    if (from == null || to == null || icon == null) return;

    final t = _moveController.value;
    final lat = from.latitude + (to.latitude - from.latitude) * t;
    final lng = from.longitude + (to.longitude - from.longitude) * t;
    final rotation = _lerpAngle(_fromRotation, _toRotation, t);

    _currentPos = LatLng(lat, lng);
    _currentRotation = rotation;

    setState(() {
      _driverMarker = Marker(
        markerId: const MarkerId('driver_self'),
        position: _currentPos!,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: rotation,
      );
    });
  }

  Future<void> _onDriverPositionUpdate(Position position) async {
    final icon = _carIcon;
    if (icon == null) return;

    final rawPoint = LatLng(position.latitude, position.longitude);

    // Snap the GPS point to the nearest road so the car glides along streets
    // instead of drifting across rooftops. Falls back to the raw point if the
    // Roads API isn't available or errors out.
    final snapped =
        await ref.read(roadSnapServiceProvider).snap(rawPoint) ?? rawPoint;

    if (!mounted) return;

    // Heading from the GPS stream is NaN when stationary and can be noisy at
    // low speeds — keep the previous heading in those cases.
    final targetRotation = (position.heading.isNaN || position.speed < 1.0)
        ? _currentRotation
        : position.heading;

    // First fix after going online: show immediately and centre the camera.
    if (_currentPos == null) {
      _currentPos = snapped;
      _currentRotation = targetRotation;
      setState(() {
        _driverMarker = Marker(
          markerId: const MarkerId('driver_self'),
          position: snapped,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: targetRotation,
        );
      });

      if (!_hasCenteredOnDriver) {
        _hasCenteredOnDriver = true;
        final controller = await _mapController.future;
        if (!mounted) return;
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(snapped, 16.5),
        );
      }
      return;
    }

    // Subsequent fixes: animate from wherever the marker currently is (even
    // mid-tween) to the new snapped target.
    _fromPos = _currentPos;
    _toPos = snapped;
    _fromRotation = _currentRotation;
    _toRotation = targetRotation;
    _moveController
      ..stop()
      ..reset()
      ..forward();
  }

  void _clearDriverMarker() {
    if (_driverMarker == null && !_hasCenteredOnDriver && _currentPos == null) {
      return;
    }
    _moveController.stop();
    setState(() {
      _driverMarker = null;
      _hasCenteredOnDriver = false;
      _currentPos = null;
      _fromPos = null;
      _toPos = null;
      _currentRotation = 0;
      _fromRotation = 0;
      _toRotation = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    // React to the driver going online/offline: stream location updates when
    // online and clear the car marker when they toggle off.
    ref.listen<DriverStatus>(driverStatusProvider, (prev, next) {
      if (next.isOffline) _clearDriverMarker();
    });

    // Push each new position fix into the marker while online.
    ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
      next.whenData(_onDriverPositionUpdate);
    });

    final status = ref.watch(driverStatusProvider);
    final isOnline = status.isOnline || status.isBusy;

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
              // When online we represent the driver with a custom car marker,
              // so hide the default blue "my location" dot to avoid overlap.
              myLocationEnabled: !isOnline,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: {
                if (isOnline && _driverMarker != null) _driverMarker!,
              },
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
