import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/constants/maps_config.dart';
import '../providers/ride_provider.dart'
    show LiveDriverPosition, RideTrackingPhase, liveDriverPositionProvider;
import '../providers/ride_search_provider.dart';
import 'driver_car_marker.dart';

/// Rider's live-tracking map.
///
/// Google Maps + a hand-drawn `BitmapDescriptor` car marker — the same
/// rendering approach the provider app already uses for the online-driver
/// marker (see `apps/provider/.../widgets/driver_car_marker.dart`). The
/// previous Mapbox + emoji / CircleAnnotation iteration never made the
/// driver dot visible during real rides; switching to the Google Maps
/// path that already works on the provider side eliminates the entire
/// class of glyph-lookup / annotation-manager bugs.
class RideRouteMap extends ConsumerStatefulWidget {
  final String destination;
  final int etaMinutes;
  final RideTrackingPhase phase;

  const RideRouteMap({
    super.key,
    required this.destination,
    required this.etaMinutes,
    this.phase = RideTrackingPhase.enRoute,
  });

  @override
  ConsumerState<RideRouteMap> createState() => _RideRouteMapState();
}

/// In-memory state of the live-track pipeline, surfaced to the on-screen
/// debug banner so the rider can see why the marker isn't appearing
/// without needing log filters.
class _LiveTrackDiagnostic {
  final String provider;
  final String marker;
  const _LiveTrackDiagnostic({required this.provider, required this.marker});
  static const empty =
      _LiveTrackDiagnostic(provider: 'awaiting first fix', marker: 'pending');
}

class _RideRouteMapState extends ConsumerState<RideRouteMap> {
  GoogleMapController? _mapController;

  /// Bitmap for the driver marker. Lazy-built on first use because canvas
  /// rendering is async — we store it once and reuse for every position
  /// update. Falls back to `BitmapDescriptor.defaultMarkerWithHue(yellow)`
  /// during the brief window before the canvas paint finishes.
  BitmapDescriptor? _carIcon;

  /// Last-known driver position. Updated by the `liveDriverPositionProvider`
  /// listener on every socket / REST fix. Drives both the driver marker's
  /// position+rotation and (after first fix) the follow-camera.
  LiveDriverPosition? _lastDriverPos;

  /// Captured once — pickup/destination don't change during a single ride.
  late final RideSearchState _searchState;

  /// Debug bus driving the on-screen diagnostic strip — toggled on every
  /// pipeline state change. Stripped from release via `kDebugMode`.
  final ValueNotifier<_LiveTrackDiagnostic> _diagnosticBus =
      ValueNotifier(_LiveTrackDiagnostic.empty);

  /// Has the camera ever fitted pickup + destination? We only do this on
  /// the first map-create; after that the camera follows the driver and
  /// we don't want to keep yanking it back.
  bool _initialBoundsFit = false;

  /// Decoded polyline for the driver→nextWaypoint route. Re-fetched when
  /// the driver drifts more than `_routeRefreshMeters` OR the phase flips
  /// (en-route ↔ in-progress, which changes the target). Cleared while
  /// the fetch is in flight so we never render two routes at once.
  List<LatLng> _routePolyline = const [];
  LatLng? _lastRoutedFrom;
  RideTrackingPhase? _lastRoutedPhase;
  DateTime? _lastRouteFetchAt;
  bool _routeFetchInFlight = false;

  /// Throttle constants — match the previous Mapbox implementation so the
  /// route doesn't refresh on every GPS bump (Google Directions is billed
  /// per call). 100 m of driver drift or 30 s elapsed since the last
  /// fetch, whichever comes first.
  static const _routeRefreshMeters = 100.0;
  static const _routeRefreshThrottle = Duration(seconds: 30);

  /// Reuse one Dio for all Directions calls. Short timeouts because the
  /// rider is staring at a stale route while we fetch — better to skip a
  /// tick than to block the UI.
  late final Dio _directionsDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  @override
  void initState() {
    super.initState();
    _searchState = ref.read(rideSearchProvider);
    // Build the car bitmap once. Anything that arrives before this
    // resolves will use the default-yellow fallback marker.
    _initCarIcon();
  }

  Future<void> _initCarIcon() async {
    try {
      final pixelRatio =
          WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final icon = await DriverCarMarker.create(
        devicePixelRatio: pixelRatio.clamp(2.0, 4.0),
      );
      if (!mounted) return;
      setState(() => _carIcon = icon);
      debugPrint('[LIVE-TRACK] car bitmap ready');
    } catch (e) {
      debugPrint('[LIVE-TRACK] car bitmap failed: $e — fallback marker used');
    }
  }

  @override
  void dispose() {
    _directionsDio.close(force: true);
    _diagnosticBus.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RideRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Phase flip (en-route → arrived → in-progress) changes the target
    // waypoint — force-refresh the route so the line doesn't keep
    // pointing at pickup after the trip starts.
    if (oldWidget.phase != widget.phase) {
      final pos = _lastDriverPos;
      if (pos != null) _syncRoute(pos);
    }
  }

  // ── Pipeline helpers ─────────────────────────────────────────────────────

  void _onDriverPosition(LiveDriverPosition? next) {
    debugPrint(
      '[LIVE-TRACK] provider tick → ${next != null ? "(${next.latitude}, ${next.longitude})" : "null"}',
    );
    setState(() => _lastDriverPos = next);
    _diagnosticBus.value = _LiveTrackDiagnostic(
      provider: next != null
          ? '(${next.latitude.toStringAsFixed(4)}, ${next.longitude.toStringAsFixed(4)})'
          : 'null',
      marker: next != null
          ? (_carIcon != null ? 'rendered (car bitmap)' : 'rendered (fallback)')
          : 'cleared',
    );
    if (next != null) {
      _followCamera(next);
      _syncRoute(next);
    }
  }

  /// Fetch a driving route from the driver's current position to the
  /// phase-appropriate waypoint (pickup while en-route/arrived, dropoff
  /// while in-progress) and store the decoded polyline in state so the
  /// map paints it.
  ///
  /// Throttled to avoid hammering Google Directions on every GPS tick —
  /// skips if the driver hasn't moved 100 m since the last fetch AND
  /// less than 30 s has passed AND the phase target hasn't flipped.
  Future<void> _syncRoute(LiveDriverPosition pos) async {
    final target = _targetForPhase();
    if (target == null) return;
    final origin = LatLng(pos.latitude, pos.longitude);

    // Skip refetch when we already have a fresh-enough route.
    final lastFrom = _lastRoutedFrom;
    final phaseChanged = _lastRoutedPhase != widget.phase;
    if (lastFrom != null && !phaseChanged && _routePolyline.isNotEmpty) {
      final drift = _haversineMeters(lastFrom, origin);
      if (drift < _routeRefreshMeters) return;
      final lastAt = _lastRouteFetchAt;
      if (lastAt != null &&
          DateTime.now().difference(lastAt) < _routeRefreshThrottle) {
        return;
      }
    }
    if (_routeFetchInFlight) return;

    _routeFetchInFlight = true;
    _lastRouteFetchAt = DateTime.now();
    try {
      final points = await _fetchGoogleRoute(origin, target);
      if (!mounted || points == null || points.length < 2) return;
      setState(() => _routePolyline = points);
      _lastRoutedFrom = origin;
      _lastRoutedPhase = widget.phase;
    } catch (e) {
      debugPrint('[LIVE-TRACK] Directions fetch failed: $e');
    } finally {
      _routeFetchInFlight = false;
    }
  }

  /// Calls Google Directions API and returns the decoded route polyline.
  /// Returns null on any non-OK response — the caller leaves the existing
  /// polyline in place so a transient network blip doesn't blank the route.
  Future<List<LatLng>?> _fetchGoogleRoute(LatLng origin, LatLng target) async {
    if (MapsConfig.apiKey.isEmpty) {
      debugPrint(
        '[LIVE-TRACK] Directions skipped — GOOGLE_MAPS_API_KEY empty. '
        'Re-run with --dart-define=GOOGLE_MAPS_API_KEY=AIza…',
      );
      return null;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${target.latitude},${target.longitude}',
        'mode': 'driving',
        'key': MapsConfig.apiKey,
      },
    );
    final response = await _directionsDio.getUri<Map<String, dynamic>>(uri);
    final data = response.data;
    if (data == null) return null;
    final status = data['status'] as String?;
    if (status != 'OK') {
      debugPrint(
        '[LIVE-TRACK] Directions non-OK status: $status — '
        '${data['error_message'] ?? '(no message)'}',
      );
      return null;
    }
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;
    final overview =
        (routes.first as Map<String, dynamic>)['overview_polyline']
            as Map<String, dynamic>?;
    final encoded = overview?['points'] as String?;
    if (encoded == null || encoded.isEmpty) return null;
    return _decodePolyline(encoded);
  }

  /// Decode Google's "encoded polyline algorithm" string to a list of
  /// LatLng points. Inline implementation so we don't add a dependency
  /// just for this one call. Reference: developers.google.com/maps/
  /// documentation/utilities/polylinealgorithm
  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Great-circle distance in metres — used to throttle route refetches.
  double _haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 + s2 * s2 * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  LatLng? _targetForPhase() {
    final pickup = _searchState.pickup;
    final dest = _searchState.destination;
    switch (widget.phase) {
      case RideTrackingPhase.inProgress:
      case RideTrackingPhase.completed:
        if (dest?.lat == null || dest?.lng == null) return null;
        return LatLng(dest!.lat!, dest.lng!);
      case RideTrackingPhase.enRoute:
      case RideTrackingPhase.arrived:
        if (pickup?.lat == null || pickup?.lng == null) return null;
        return LatLng(pickup!.lat!, pickup.lng!);
      case RideTrackingPhase.cancelled:
        return null;
    }
  }

  Future<void> _followCamera(LiveDriverPosition pos) async {
    final mc = _mapController;
    if (mc == null) return;
    final target = _targetForPhase();
    if (target == null) {
      // No phase-target — just centre on the driver.
      await mc.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
      return;
    }
    final bounds = _boundsFromTwo(
      LatLng(pos.latitude, pos.longitude),
      target,
    );
    try {
      await mc.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (_) {
      // Bounds fit fails on a freshly-mounted map with no layout pass yet.
      // Fall back to centring on the driver — the next tick re-tries.
      await mc.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }
  }

  Future<void> _fitInitialBounds() async {
    final mc = _mapController;
    if (mc == null || _initialBoundsFit) return;
    final pickup = _searchState.pickup;
    final dest = _searchState.destination;
    if (pickup?.lat == null || dest?.lat == null) return;
    final bounds = _boundsFromTwo(
      LatLng(pickup!.lat!, pickup.lng!),
      LatLng(dest!.lat!, dest.lng!),
    );
    try {
      await mc.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      _initialBoundsFit = true;
    } catch (_) {
      // Same first-frame race as in _followCamera — retry on next tick.
    }
  }

  LatLngBounds _boundsFromTwo(LatLng a, LatLng b) {
    final minLat = a.latitude < b.latitude ? a.latitude : b.latitude;
    final maxLat = a.latitude > b.latitude ? a.latitude : b.latitude;
    final minLng = a.longitude < b.longitude ? a.longitude : b.longitude;
    final maxLng = a.longitude > b.longitude ? a.longitude : b.longitude;
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _onMapCreated(GoogleMapController mc) async {
    _mapController = mc;
    debugPrint('[LIVE-TRACK] Google Map ready');
    _diagnosticBus.value = _LiveTrackDiagnostic(
      provider: _diagnosticBus.value.provider,
      marker: 'map ready',
    );

    // Pick up any driver fix that arrived before the map mounted.
    final pos = ref.read(liveDriverPositionProvider);
    if (pos != null) {
      _onDriverPosition(pos);
    } else {
      await _fitInitialBounds();
    }
  }

  // ── Marker construction ─────────────────────────────────────────────────

  Set<Polyline> _buildPolylines() {
    if (_routePolyline.length < 2) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('driverRoute'),
        points: _routePolyline,
        width: 5,
        // primaryGold for visual consistency with the in-app accent.
        color: MyShopColors.primaryGold,
        // Smooth joins so the line doesn't look segmented around bends.
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final pickup = _searchState.pickup;
    final dest = _searchState.destination;

    if (pickup?.lat != null && pickup?.lng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pickup!.lat!, pickup.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
      );
    }

    if (dest?.lat != null && dest?.lng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(dest!.lat!, dest.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    final pos = _lastDriverPos;
    if (pos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(pos.latitude, pos.longitude),
          // Use the custom car bitmap if it finished rendering; otherwise
          // a default-yellow marker so the driver is visible from frame 1.
          icon: _carIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow,
              ),
          rotation: pos.heading ?? 0,
          // Anchor at the centre so rotation pivots on the visual middle
          // of the car (matches the square bitmap's centre).
          anchor: const Offset(0.5, 0.5),
          flat: true, // Marker stays flat against the map when tilted.
          infoWindow: const InfoWindow(title: 'Driver'),
        ),
      );
    }

    return markers;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Re-sync on every driver-position tick. ref.listen survives rebuilds.
    ref.listen<LiveDriverPosition?>(liveDriverPositionProvider, (_, next) {
      _onDriverPosition(next);
    });

    final pickup = _searchState.pickup;
    final dest = _searchState.destination;
    // Pick a reasonable starting centre — favour pickup, fall back to
    // destination, fall back to a hardcoded Kumasi centroid.
    final initialCenter = pickup?.lat != null
        ? LatLng(pickup!.lat!, pickup.lng!)
        : dest?.lat != null
            ? LatLng(dest!.lat!, dest.lng!)
            : const LatLng(6.6885, -1.6244);

    final statusBarHeight = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            key: const ValueKey('rideRouteMap'),
            initialCameraPosition: CameraPosition(
              target: initialCenter,
              zoom: 14,
            ),
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            // Required for Android — sometimes the platform view needs a
            // single hint to be touchable in stacked layouts. Identical
            // pattern the pickup/destination picker uses.
            gestureRecognizers: const {},
            onMapCreated: _onMapCreated,
          ),
        ),
        Positioned(
          top: statusBarHeight + 10,
          left: 0,
          right: 0,
          child: Center(child: _topPill()),
        ),
        Positioned(
          top: statusBarHeight + 62,
          left: 16,
          right: 16,
          child: _DestinationOverlay(destination: widget.destination),
        ),
        if (kDebugMode)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _LiveTrackDebugBanner(bus: _diagnosticBus),
          ),
      ],
    );
  }

  Widget _topPill() {
    switch (widget.phase) {
      case RideTrackingPhase.enRoute:
        return _EtaPill(etaMinutes: widget.etaMinutes);
      case RideTrackingPhase.arrived:
        return const _ArrivedPill();
      case RideTrackingPhase.inProgress:
        return _InProgressPill(minutes: widget.etaMinutes);
      case RideTrackingPhase.completed:
      case RideTrackingPhase.cancelled:
        return _InProgressPill(minutes: widget.etaMinutes);
    }
  }
}

// ── Destination ("HEADING TO") card ───────────────────────────────────────────

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );

/// Debug-only diagnostic strip — visible in debug builds so the rider can
/// see why the live driver marker isn't appearing without filtering logs.
class _LiveTrackDebugBanner extends StatelessWidget {
  const _LiveTrackDebugBanner({required this.bus});

  final ValueNotifier<_LiveTrackDiagnostic> bus;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_LiveTrackDiagnostic>(
      valueListenable: bus,
      builder: (_, value, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LIVE-TRACK DEBUG',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'provider: ${value.provider}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              'marker:   ${value.marker}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationOverlay extends StatelessWidget {
  final String destination;
  const _DestinationOverlay({required this.destination});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: _cardDecoration(),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _RouteRail(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'HEADING TO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textSecondary,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    destination,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status pills ──────────────────────────────────────────────────────────────

class _EtaPill extends StatelessWidget {
  final int etaMinutes;
  const _EtaPill({required this.etaMinutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined,
              size: 14, color: MyShopColors.textPrimary),
          const SizedBox(width: 6),
          Text(
            'ARRIVING IN $etaMinutes MINS',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrivedPill extends StatelessWidget {
  const _ArrivedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: MyShopColors.success,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: MyShopColors.success.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'YOUR DRIVER IS HERE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _InProgressPill extends StatelessWidget {
  final int minutes;
  const _InProgressPill({required this.minutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: MyShopColors.darkSlate,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            'IN TRANSIT · $minutes MIN',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gold rail — filled dot → dashed vertical line → outlined circle.
class _RouteRail extends StatelessWidget {
  const _RouteRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: MyShopColors.primaryGold,
            ),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: CustomPaint(painter: _DashedLinePainter()),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: MyShopColors.primaryGold, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MyShopColors.primaryGold
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const dash = 2.0;
    const gap = 3.0;
    final cx = size.width / 2;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
