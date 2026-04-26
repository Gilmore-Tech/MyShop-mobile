import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:go_router/go_router.dart';

import '../../../core/services/directions_service.dart';
import '../providers/driver_location_provider.dart';
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
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// Live distance/ETA pushed up from [_NavigationMap] on each GPS fix.
  /// The header reads it via [ValueListenableBuilder] so the text ticks
  /// down without forcing the GoogleMap to rebuild.
  final ValueNotifier<_LiveMetrics> _liveMetrics =
      ValueNotifier<_LiveMetrics>(const _LiveMetrics());

  /// Lets the recenter button ask the map to refit without holding the
  /// GoogleMapController itself — keeps native resources scoped to the map
  /// widget.
  final _MapHandle _mapHandle = _MapHandle();

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
    // Note: `accepted → driver_en_route` is fired directly from
    // `ActiveRideNotifier.acceptRide` so it lands the moment the socket
    // ack returns, regardless of when this screen mounts. The backend's
    // stage-timeout service auto-cancels rides stuck in `accepted` after
    // ~2 minutes, so we can't risk the transition being delayed by widget
    // lifecycle quirks.
  }

  @override
  void dispose() {
    _proximityTimer?.cancel();
    _sheetController.dispose();
    _liveMetrics.dispose();
    super.dispose();
  }

  Future<void> _handlePrimaryAction(Ride ride) async {
    final notifier = ref.read(activeRideProvider.notifier);
    final ok = switch (ride.status) {
      RideStatus.accepted ||
      RideStatus.driverEnRoute =>
        await notifier.markArrived(),
      RideStatus.arrived => await notifier.startTrip(),
      RideStatus.inProgress => await notifier.completeTrip(),
      _ => false,
    };
    if (!mounted) return;
    if (!ok) {
      final message = ref.read(activeRideProvider).errorMessage ??
          "Couldn't update the ride";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    // The activeRideProvider listener below handles navigation when the
    // ride hits a terminal state (completed → trip summary, cancelled →
    // back to home). Don't pop from here — that double-pop was leaving
    // the navigator on a black screen below the home shell.
  }

  /// Bottom sheet with the "off the happy path" actions — currently just
  /// "Cancel ride", which is the only reliable way out when the backend's
  /// status PATCH is failing (e.g. Prisma errors during `complete`) and
  /// the driver would otherwise be stuck on this screen forever.
  Future<void> _showOverflowMenu(Ride ride) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MyShopColors.surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            ListTile(
              leading: const Icon(Icons.cancel_outlined,
                  color: MyShopColors.error),
              title: const Text('Cancel ride',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.error,
                  )),
              subtitle: const Text(
                  "Notify the rider and free yourself for the next trip."),
              onTap: () => Navigator.of(sheetCtx).pop('cancel'),
            ),
            const SizedBox(height: MyShopSpacing.sm),
          ],
        ),
      ),
    );
    if (action != 'cancel' || !mounted) return;
    await _confirmAndCancel(ride);
  }

  Future<void> _confirmAndCancel(Ride ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text(
          'The rider will be notified. Frequent cancellations affect your '
          'driver rating.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(activeRideProvider.notifier).cancelRide();
    if (!mounted) return;
    // Active ride state is now cleared; pop back to whatever was below us.
    Navigator.of(context).pop('cancelled');
  }

  /// Where the driver is currently navigating to. Pickup until they have
  /// the passenger in the car; drop-off after the trip starts.
  LatLng _routingTarget(Ride ride) {
    return switch (ride.status) {
      RideStatus.inProgress => LatLng(ride.dropoffLat, ride.dropoffLng),
      _ => LatLng(ride.pickupLat, ride.pickupLng),
    };
  }

  String _targetLabel(RideStatus status) {
    return switch (status) {
      RideStatus.accepted ||
      RideStatus.driverEnRoute =>
        'TO PICKUP',
      RideStatus.arrived => 'AT PICKUP',
      RideStatus.inProgress => 'TO DESTINATION',
      _ => 'TO DESTINATION',
    };
  }

  String _targetAddress(Ride ride) {
    return switch (ride.status) {
      RideStatus.inProgress => ride.dropoffAddress,
      _ => ride.pickupAddress,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeRideProvider);
    // When the backend tells us the ride has reached a terminal state,
    // navigate off this screen so the driver isn't stuck tapping buttons
    // that 400 every time.
    //
    //   - `completed`: replace this screen with the trip-summary so the
    //     driver lands on the earnings summary. Don't `clearRide()` here
    //     — DriverRideCompleteScreen reads the ride/state and clears it
    //     itself when the user dismisses.
    //   - `cancelled`: snackbar + clear state + pop. There's no summary
    //     screen for a cancelled ride.
    ref.listen<ActiveRideState>(activeRideProvider, (prev, next) {
      final wasActive = prev?.ride?.status.isActive ?? false;
      final nextStatus = next.ride?.status;
      if (!wasActive) return;
      if (!mounted) return;
      if (nextStatus == RideStatus.completed) {
        // Use GoRouter so the underlying nav stack stays consistent —
        // pushReplacement on a raw MaterialPageRoute would replace the
        // GoRoute entry and leave nothing on the stack to pop back to,
        // which is the "black screen on back" the driver was seeing.
        context.go('/ride-complete');
        return;
      }
      if (nextStatus == RideStatus.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This ride was cancelled.')),
        );
        ref.read(activeRideProvider.notifier).clearRide();
        Navigator.of(context).pop('cancelled');
      }
    });

    final ride = state.ride;
    if (ride == null) {
      return const Scaffold(
        body: Center(child: Text('No active ride')),
      );
    }
    final isUpdating = state.isUpdating;
    final target = _routingTarget(ride);
    final targetLabel = _targetLabel(ride.status);
    final targetAddress = _targetAddress(ride);

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: Stack(
        children: [
          // ── Full-screen navigation map. Owns its own controller, GPS
          //    subscription, and Directions cache; rebuilding the parent
          //    Stack does not churn the platform-view bridge.
          Positioned.fill(
            child: RepaintBoundary(
              child: _NavigationMap(
                target: target,
                handle: _mapHandle,
                metrics: _liveMetrics,
              ),
            ),
          ),

          // ── Navigation header — rebuilds on every metrics tick (cheap
          //    text only), independent of the GoogleMap.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<_LiveMetrics>(
              valueListenable: _liveMetrics,
              builder: (context, metrics, _) {
                return _NavigationHeader(
                  phaseLabel: targetLabel,
                  address: targetAddress,
                  liveDistanceMeters: metrics.distanceMeters,
                  liveEtaMinutes: metrics.etaMinutes,
                );
              },
            ),
          ),

          // ── Map controls: recenter + overflow + SOS ──
          Positioned(
            right: MyShopSpacing.md,
            top: MediaQuery.of(context).padding.top + 130,
            child: Column(
              children: [
                _MapControlButton(
                  icon: Icons.my_location,
                  onTap: () => _mapHandle.recenter?.call(),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                _MapControlButton(
                  icon: Icons.more_vert,
                  onTap: () => _showOverflowMenu(ride),
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
                isUpdating: isUpdating,
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
  const _NavigationHeader({
    required this.phaseLabel,
    required this.address,
    required this.liveDistanceMeters,
    required this.liveEtaMinutes,
  });

  /// e.g. "TO PICKUP" / "TO DESTINATION" — drives the small label above the
  /// distance reading.
  final String phaseLabel;

  /// The address the driver is currently navigating to. Pickup until the
  /// trip starts, drop-off afterwards.
  final String address;

  /// Straight-line distance from current GPS to [address], in meters.
  /// Recomputed on every GPS fix so the label ticks down live.
  final double? liveDistanceMeters;

  /// Estimated minutes remaining, derived from the Directions route's
  /// average road speed applied to [liveDistanceMeters]. Null until we have
  /// both a GPS fix and a successful Directions response.
  final int? liveEtaMinutes;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final distanceLabel = liveDistanceMeters != null
        ? (liveDistanceMeters! < 1000
            ? '${liveDistanceMeters!.round()} m'
            : '${(liveDistanceMeters! / 1000).toStringAsFixed(1)} km')
        : '— km';
    final etaLabel = (liveEtaMinutes != null && liveEtaMinutes! > 0)
        ? '${liveEtaMinutes!} min'
        : (liveEtaMinutes == 0 ? 'Arriving' : '—');
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(distanceLabel,
                      style: const TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: MyShopColors.textPrimary)),
                  Text(address,
                      style: const TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 12,
                          color: MyShopColors.textSecondary),
                      maxLines: 1,
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
                Text(phaseLabel,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.primaryGold,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(etaLabel,
                    style: const TextStyle(
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

// ─── Live metrics + map handle ──────────────────────────────────────────────

class _LiveMetrics {
  const _LiveMetrics({this.distanceMeters, this.etaMinutes});

  /// Straight-line distance from current GPS to the routing target, in
  /// meters. Null until we get the first fix.
  final double? distanceMeters;

  /// Estimated minutes remaining, derived from the Directions route's
  /// average road speed applied to [distanceMeters].
  final int? etaMinutes;
}

/// Recenter shim — handed to [_NavigationMap] so it can register a callback
/// the parent can fire without holding the native controller itself.
class _MapHandle {
  VoidCallback? recenter;
}

// ─── Navigation map ─────────────────────────────────────────────────────────
//
// Owns the GoogleMap, its controller, the Directions route cache, and the
// GPS subscription. Crucially this widget is the only thing that watches
// `driverLocationStreamProvider`, so a new fix triggers a setState INSIDE
// this widget only — the parent Stack doesn't rebuild and the platform-view
// bridge isn't churned every second.
//
// Mirrors the artisan-side _NavigationMap in active_job_screen.dart.

class _NavigationMap extends ConsumerStatefulWidget {
  const _NavigationMap({
    required this.target,
    required this.handle,
    required this.metrics,
  });

  final LatLng target;
  final _MapHandle handle;
  final ValueNotifier<_LiveMetrics> metrics;

  @override
  ConsumerState<_NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends ConsumerState<_NavigationMap> {
  GoogleMapController? _mapController;
  DirectionsRoute? _route;
  bool _routeLoading = false;
  bool _hasFittedCamera = false;

  /// Origin (driver GPS) used when the last route was fetched — lets us skip
  /// a refetch if the GPS fix has barely moved.
  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteFetchAt;

  /// Most recent GPS fix. Stored in a field rather than via ref.watch so the
  /// GoogleMap only rebuilds when this widget calls setState.
  LatLng? _driver;

  Set<Marker> _markers = const <Marker>{};
  Set<Polyline> _polylines = const <Polyline>{};

  static const _routeRefreshMeters = 80.0;
  static const _routeRefreshThrottle = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    widget.handle.recenter = _handleRecenter;
    _markers = _buildMarkers();
  }

  @override
  void didUpdateWidget(covariant _NavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Phase changed (e.g. pickup → dropoff after trip starts). Drop the
    // cached route + refit the camera so we navigate to the new target.
    if (oldWidget.target.latitude != widget.target.latitude ||
        oldWidget.target.longitude != widget.target.longitude) {
      _route = null;
      _lastRouteOrigin = null;
      _lastRouteFetchAt = null;
      _hasFittedCamera = false;
      _markers = _buildMarkers();
      _polylines = const <Polyline>{};
      final driver = _driver;
      if (driver != null) {
        _refreshRouteIfNeeded(driver, force: true);
      }
      _publishMetrics();
    }
  }

  @override
  void dispose() {
    if (widget.handle.recenter == _handleRecenter) {
      widget.handle.recenter = null;
    }
    _mapController?.dispose();
    super.dispose();
  }

  void _handleRecenter() {
    final driver = _driver;
    if (driver == null) return;
    _hasFittedCamera = false;
    _fitCamera(origin: driver, route: _route);
    _refreshRouteIfNeeded(driver, force: true);
  }

  Future<void> _refreshRouteIfNeeded(
    LatLng origin, {
    bool force = false,
  }) async {
    if (_routeLoading) return;

    if (!force) {
      final last = _lastRouteOrigin;
      if (last != null && _route != null) {
        final drift = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          origin.latitude,
          origin.longitude,
        );
        if (drift < _routeRefreshMeters) return;
      }
      final lastAt = _lastRouteFetchAt;
      if (lastAt != null &&
          DateTime.now().difference(lastAt) < _routeRefreshThrottle) {
        return;
      }
    }

    _routeLoading = true;
    _lastRouteFetchAt = DateTime.now();
    try {
      final route = await ref.read(directionsServiceProvider).fetchRoute(
            origin: origin,
            destination: widget.target,
          );
      if (!mounted) return;
      setState(() {
        _route = route;
        _lastRouteOrigin = origin;
        _polylines = _buildPolylines();
      });
      _fitCamera(origin: origin, route: route);
      _publishMetrics();
    } finally {
      _routeLoading = false;
    }
  }

  void _onPositionFix(Position pos) {
    if (!mounted) return;
    final next = LatLng(pos.latitude, pos.longitude);
    final prev = _driver;

    if (prev != null &&
        prev.latitude == next.latitude &&
        prev.longitude == next.longitude) {
      return;
    }

    setState(() {
      _driver = next;
      _markers = _buildMarkers();
    });
    _publishMetrics();
    _refreshRouteIfNeeded(next);
  }

  void _publishMetrics() {
    final driver = _driver;
    if (driver == null) {
      widget.metrics.value = const _LiveMetrics();
      return;
    }
    final distance = _haversineMeters(driver, widget.target);
    widget.metrics.value = _LiveMetrics(
      distanceMeters: distance,
      etaMinutes: _liveEtaMinutes(distance, _route),
    );
  }

  Set<Marker> _buildMarkers() {
    final driver = _driver;
    return <Marker>{
      Marker(
        markerId: const MarkerId('target'),
        position: widget.target,
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };
  }

  Set<Polyline> _buildPolylines() {
    final route = _route;
    if (route == null || route.polyline.length < 2) {
      return const <Polyline>{};
    }
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: route.polyline,
        color: MyShopColors.primaryGold,
        width: 5,
        patterns: route.isFallback
            ? [PatternItem.dash(20), PatternItem.gap(12)]
            : const [],
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  void _fitCamera({required LatLng origin, required DirectionsRoute? route}) {
    final controller = _mapController;
    if (controller == null) return;
    if (_hasFittedCamera && route == null) return;

    // Guard against absurd bounds (bad GPS, bad ride coords) — same reason
    // as the artisan screen: a continent-wide bound triggers iOS jetsam.
    final straightLineMeters = _haversineMeters(origin, widget.target);
    if (straightLineMeters > 100000) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(origin, 14));
      _hasFittedCamera = true;
      return;
    }

    final points = (route != null && route.polyline.isNotEmpty)
        ? route.polyline
        : <LatLng>[origin, widget.target];
    double south = points.first.latitude;
    double north = points.first.latitude;
    double west = points.first.longitude;
    double east = points.first.longitude;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        80,
      ),
    );
    _hasFittedCamera = true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Position>>(driverLocationStreamProvider,
        (prev, next) {
      next.whenData(_onPositionFix);
    });

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _driver ?? widget.target,
        zoom: 14,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        final driver = _driver;
        if (driver != null) {
          _fitCamera(origin: driver, route: _route);
        }
      },
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 100,
        bottom: 220,
      ),
      markers: _markers,
      polylines: _polylines,
    );
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 + s2 * s2 * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  /// Estimated minutes derived from the Directions response's average road
  /// speed. Falls back to ~30 km/h until we have a real route.
  static int? _liveEtaMinutes(
    double? meters,
    DirectionsRoute? route,
  ) {
    if (meters == null) return null;
    double? mps;
    if (route != null &&
        !route.isFallback &&
        route.durationSeconds > 0 &&
        route.distanceMeters > 0) {
      mps = route.distanceMeters / route.durationSeconds;
    }
    mps ??= 8.333;
    return (meters / mps / 60).round();
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
    required this.isUpdating,
    required this.onPrimaryAction,
  });

  final Ride ride;
  final ScrollController scrollController;
  final bool isUpdating;
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
                      _ClientAvatar(photoUrl: ride.clientPhotoUrl, size: 56),
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
                onPressed: isUpdating ? null : onPrimaryAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.darkSlate,
                  foregroundColor: MyShopColors.textOnPrimary,
                  disabledBackgroundColor:
                      MyShopColors.darkSlate.withValues(alpha: 0.6),
                  disabledForegroundColor: MyShopColors.textOnPrimary,
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
                child: isUpdating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(
                              MyShopColors.textOnPrimary),
                        ),
                      )
                    : Row(
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

/// Round avatar that loads `photoUrl` over the network when available and
/// falls back to a generic person icon while loading or on error.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.photoUrl, required this.size});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) return _placeholder();
    final cacheDim = (size * 3).round();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cacheDim,
        memCacheHeight: cacheDim,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFFCEAE1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: size * 0.5,
        color: MyShopColors.textSecondary,
      ),
    );
  }
}
