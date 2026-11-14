import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:shared_utils/shared_utils.dart';

import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/socket_provider.dart';
import '../../profile/providers/verification_provider.dart';
import '../../promos/widgets/promos_section.dart';
import '../data/gps_position_smoother.dart';
import '../providers/driver_location_provider.dart';
import '../providers/surge_provider.dart';
import '../widgets/surge_heatmap.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../screens/ride_request_screen.dart';
import '../widgets/driver_car_marker.dart';
import '../widgets/driver_home_header.dart';
import '../widgets/earnings_summary_section.dart';
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
  GoogleMapController? _googleMapController;

  // Kumasi, Ashanti Region — fallback centre when location is unavailable.
  static const _kumasiCenter = LatLng(6.6885, -1.6244);

  BitmapDescriptor? _carIcon;
  Marker? _driverMarker;

  /// Animates the marker from the last rendered point to the next locally
  /// smoothed GPS fix so the car glides rather than teleporting on each update.
  late final AnimationController _moveController;

  final VehicleMotion _driverMotion = VehicleMotion();
  Duration _lastRenderedFrame = Duration.zero;
  LatLng? _currentPos;
  double _currentRotation = 0;
  final GpsPositionSmoother _positionSmoother = GpsPositionSmoother();

  /// Guards camera auto-follow so we only animate on the first location fix
  /// after each online session (we don't want to fight the user if they pan).
  bool _hasCenteredOnDriver = false;

  /// While online and idle, keep the driver's car visible as they move around.
  /// If the user manually pans/zooms the map we pause follow mode; tapping the
  /// recenter control restores it.
  bool _followDriverCamera = true;
  bool _programmaticCameraMove = false;
  Timer? _programmaticCameraMoveTimer;

  @override
  void initState() {
    super.initState();
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(_onAnimationTick);
    _loadCarIcon();
    _goToCurrentLocation(requestPermissionIfNeeded: false);
  }

  @override
  void dispose() {
    _moveController
      ..removeListener(_onAnimationTick)
      ..dispose();
    _programmaticCameraMoveTimer?.cancel();
    _googleMapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCarIcon() async {
    final pixelRatio =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final icon = await DriverCarMarker.create(devicePixelRatio: pixelRatio);
    if (!mounted) return;
    setState(() => _carIcon = icon);
  }

  Future<void> _goToCurrentLocation(
      {bool requestPermissionIfNeeded = true}) async {
    // Startup only warms an already-authorized location. Sensitive permission
    // prompts are reserved for an explicit recenter or Go Online action.
    final cached = ref.read(lastKnownPositionProvider);
    if (cached != null) {
      try {
        if (!mounted) return;
        await _animateCameraTo(
          LatLng(cached.latitude, cached.longitude),
          zoom: 15,
        );
      } catch (_) {
        /* map controller may not be ready yet — listener picks it up */
      }
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermissionIfNeeded) {
      // Re-check just before prompting in case another explicit flow completed
      // while this one was waiting.
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        try {
          permission = await Geolocator.requestPermission();
        } catch (e) {
          debugPrint(
            '[LOC] requestPermission race — letting warm-up finish: $e',
          );
          return;
        }
      }
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('[LOC] permission $permission — staying on Kumasi fallback');
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LOC] services disabled — staying on Kumasi fallback');
      return;
    }

    // Fast path: use the OS-cached last fix so the map centres in <100ms even
    // when getCurrentPosition() is slow or temporarily failing (common on
    // iOS when the GPS sensor hasn't settled yet, see kCLErrorDomain 0).
    Position? position;
    try {
      position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        debugPrint('[LOC] using last-known location fix');
      }
    } catch (e) {
      debugPrint('[LOC] getLastKnownPosition failed: $e');
    }

    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      position = fresh;
      debugPrint('[LOC] got fresh location fix');
    } catch (e) {
      // Common on iOS when sensor isn't settled — fall back to lastKnown
      // (already loaded above) so the map at least leaves Kumasi.
      debugPrint('[LOC] getCurrentPosition failed: $e');
    }

    if (position == null) return;

    // Geolocator can park us here for up to 8 s — if the user navigated
    // away during the wait, `ref` is dead and any read throws StateError.
    if (!mounted) return;

    // Cache the fix so other screens (edit business info, etc.) can centre
    // their maps on the driver without re-prompting for permission.
    ref.read(lastKnownPositionProvider.notifier).state = position;
    if (!mounted) return;
    await _animateCameraTo(
      LatLng(position.latitude, position.longitude),
      zoom: 15,
    );
  }

  Future<void> _animateCameraTo(LatLng target, {required double zoom}) async {
    final controller = await _mapController.future;
    if (!mounted) return;
    _programmaticCameraMove = true;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    _programmaticCameraMoveTimer?.cancel();
    _programmaticCameraMoveTimer = Timer(const Duration(milliseconds: 700), () {
      _programmaticCameraMove = false;
    });
  }

  Future<void> _recenterOnDriver() async {
    _followDriverCamera = true;
    final current = _currentPos;
    if (current != null) {
      await _animateCameraTo(current, zoom: 16.5);
      return;
    }

    final cached = ref.read(lastKnownPositionProvider);
    if (cached != null) {
      await _animateCameraTo(
        LatLng(cached.latitude, cached.longitude),
        zoom: 15,
      );
      return;
    }

    await _goToCurrentLocation();
  }

  // A ticker clock makes presentation independent of wall-clock corrections.
  DateTime _motionNow = DateTime.now();
  DateTime? _motionEpoch;

  void _onAnimationTick() {
    final icon = _carIcon;
    if (icon == null) return;
    final elapsed = _moveController.lastElapsedDuration ??
        (_moveController.value >= 1 ? _driverMotion.duration : Duration.zero);
    if (_motionEpoch != null) _motionNow = _motionEpoch!.add(elapsed);
    if (_driverMotion.duration > Duration.zero &&
        _moveController.value < 1 &&
        elapsed - _lastRenderedFrame < const Duration(milliseconds: 32)) {
      return;
    }
    _lastRenderedFrame = elapsed;
    final pose = _driverMotion.sample(_motionNow);
    if (pose == null || !mounted) return;
    _currentPos = LatLng(pose.point.latitude, pose.point.longitude);
    _currentRotation = pose.heading;
    setState(() {
      _driverMarker = Marker(
        markerId: const MarkerId('driver_self'),
        position: _currentPos!,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        rotation: pose.heading,
      );
    });
  }

  Future<void> _onDriverPositionUpdate(Position position) async {
    final icon = _carIcon;
    if (icon == null) return;

    final displayPoint = _positionSmoother.filter(
      point: LatLng(position.latitude, position.longitude),
      accuracyMeters: position.accuracy,
      speedMetersPerSecond: position.speed,
      timestamp: position.timestamp,
    );

    if (!mounted) return;

    // Heading from the GPS stream is NaN when stationary and can be noisy at
    // low speeds — keep the previous heading in those cases.
    final targetRotation = (position.heading.isNaN || position.speed < 1.0)
        ? _currentRotation
        : position.heading;

    final firstFix = _currentPos == null;
    final accepted = _driverMotion.update(
      point: (
        latitude: displayPoint.latitude,
        longitude: displayPoint.longitude
      ),
      heading: targetRotation,
      fixAt: position.timestamp,
      now: _motionNow,
    );
    if (!accepted) return;
    // Use the actual fix cadence, rather than a fixed 900 ms dash followed by
    // a pause. Both heading and position continue from the displayed pose.
    _moveController.stop();
    _motionEpoch = _motionNow;
    _lastRenderedFrame = Duration.zero;
    if (_driverMotion.duration > Duration.zero) {
      _moveController.duration = _driverMotion.duration;
      _moveController.forward(from: 0);
    } else {
      _onAnimationTick();
    }
    if (firstFix && !_hasCenteredOnDriver) {
      _hasCenteredOnDriver = true;
      await _animateCameraTo(displayPoint, zoom: 16.5);
      return;
    }

    if (_followDriverCamera) {
      await _animateCameraTo(displayPoint, zoom: 16.5);
    }
  }

  void _clearDriverMarker() {
    if (_driverMarker == null && !_hasCenteredOnDriver && _currentPos == null) {
      return;
    }
    _moveController.stop();
    _positionSmoother.reset();
    _driverMotion.reset();
    setState(() {
      _driverMarker = null;
      _hasCenteredOnDriver = false;
      _currentPos = null;
      _followDriverCamera = true;
      _currentRotation = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Eagerly load verification status so profileCompletionProvider has data
    // ready when the user taps "Go Online" (avoids the false "checking your
    // profile — please try again" snackbar from a cold first read).
    ref.watch(verificationStatusProvider);

    // React to the driver going online/offline: stream location updates when
    // online and clear the car marker when they toggle off.
    ref.listen<DriverStatus>(providerStatusProvider, (prev, next) {
      if (next.isOffline) _clearDriverMarker();
    });

    // Push each new position fix into the marker while online.
    ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
      next.whenData(_onDriverPositionUpdate);
    });

    // While offline, the position-stream listener above is dormant — but the
    // app-level warm-up in `main.dart` still pushes a fresh fix into
    // `lastKnownPositionProvider` shortly after launch. Animate the camera
    // off the Kumasi fallback once that fix arrives so the driver doesn't
    // see the pilot-city flash until they toggle online.
    ref.listen<Position?>(lastKnownPositionProvider, (prev, next) async {
      if (next == null) return;
      if (_hasCenteredOnDriver) return;
      if (prev != null) return;
      if (!mounted) return;
      await _animateCameraTo(LatLng(next.latitude, next.longitude), zoom: 15);
    });

    final surgeAreas = ref.watch(surgeAreasProvider);
    final status = ref.watch(providerStatusProvider);
    final isOnline = status.isOnline || status.isBusy;

    // Prefer the last-known device fix so re-opens centre on the driver
    // immediately instead of flashing Kumasi before the GPS animate kicks in.
    final cached = ref.watch(lastKnownPositionProvider);
    final initialTarget = cached == null
        ? _kumasiCenter
        : LatLng(cached.latitude, cached.longitude);
    final showNativeLocationLayer = !isOnline && cached != null;

    return Scaffold(
      body: Stack(
        children: [
          // ── 1. Full-screen Google Map ──
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 15,
              ),
              onMapCreated: (controller) {
                _googleMapController = controller;
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
                final current = _currentPos;
                if (current != null && isOnline) {
                  unawaited(_animateCameraTo(current, zoom: 16.5));
                }
              },
              onCameraMoveStarted: () {
                if (_programmaticCameraMove) return;
                if (_followDriverCamera) {
                  setState(() => _followDriverCamera = false);
                }
              },
              // When online we represent the driver with a custom car marker,
              // so hide the default blue "my location" dot to avoid overlap.
              myLocationEnabled: showNativeLocationLayer,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: {if (isOnline && _driverMarker != null) _driverMarker!},
              polygons: surgeHeatmapPolygons(surgeAreas, onTap: (area) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '${area.name} · ${area.multiplier.toStringAsFixed(2)}× fares')));
              }),
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

          Positioned(
            top: 219,
            right: MyShopSpacing.md,
            child: _MapRecenterButton(onTap: _recenterOnDriver),
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
                          color: MyShopColors.surfaceGrey.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),

                    // Online/Offline toggle
                    const OnlineOfflineToggle(),

                    // Earnings summary
                    const EarningsSummarySection(),

                    // Auto-accept toggle removed for now — to be reintroduced
                    // as the feature is built out (widget retained in
                    // auto_accept_card.dart).
                    const SizedBox(height: MyShopSpacing.lg),

                    // Provider-audience promos (commission relief).
                    // Collapses to zero height when none are active —
                    // promo failures must never break home.
                    const PromosSection(),

                    // Recent Activity
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: MyShopSpacing.md,
                      ),
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
            BoxShadow(color: Color(0x14171A1F), blurRadius: 2),
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

class _MapRecenterButton extends StatelessWidget {
  const _MapRecenterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
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
            BoxShadow(color: Color(0x14171A1F), blurRadius: 2),
          ],
        ),
        child: const Icon(
          Icons.my_location,
          color: MyShopColors.textPrimary,
          size: 22,
        ),
      ),
    );
  }
}
