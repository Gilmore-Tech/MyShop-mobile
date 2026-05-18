import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    show
        CameraOptions,
        CircleAnnotation,
        CircleAnnotationManager,
        CircleAnnotationOptions,
        CompassSettings,
        CoordinateBounds,
        LineString,
        MapWidget,
        MapboxMap,
        MbxEdgeInsets,
        PointAnnotationManager,
        PointAnnotationOptions,
        Point,
        PolylineAnnotation,
        PolylineAnnotationManager,
        PolylineAnnotationOptions,
        Position,
        ScaleBarSettings;
import 'package:shared_ui/shared_ui.dart';

import '../../../core/constants/mapbox_config.dart';
import '../../../core/providers/current_location_provider.dart';
import '../providers/ride_provider.dart'
    show LiveDriverPosition, RideTrackingPhase, liveDriverPositionProvider;
import '../providers/ride_search_provider.dart';

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

class _RideRouteMapState extends ConsumerState<RideRouteMap> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _annotationManager;
  PolylineAnnotationManager? _polylineManager;

  /// Dedicated manager for the driver-car circle markers (outer halo +
  /// inner solid dot). Circle annotations render purely from the Mapbox
  /// style sheet rather than a font-glyph lookup, so they never fall back
  /// to an empty square the way the 🚗 emoji can on styles that don't
  /// ship a colour-emoji font (the original v1.0 emoji marker silently
  /// vanished on the Mapbox Streets style — that's the "marker never
  /// appears" symptom reported during testing).
  CircleAnnotationManager? _driverCircleManager;
  CircleAnnotation? _driverHaloAnnotation;
  CircleAnnotation? _driverDotAnnotation;

  /// The on-map polyline tracing the driver's road route to the next
  /// waypoint (pickup while en-route/arrived, destination while in-progress).
  /// Stored so we can update its geometry in place rather than re-create.
  PolylineAnnotation? _routeAnnotation;

  /// Origin (driver lat/lng) used for the most recent successful Directions
  /// fetch — lets us skip refetches while the driver hasn't moved much.
  Position? _lastRoutedFromCoord;
  RideTrackingPhase? _lastRoutedPhase;
  DateTime? _lastRouteFetchAt;
  bool _routeFetchInFlight = false;

  /// Reuse a single Dio instance for the Mapbox Directions API. Configured
  /// with short timeouts because the rider is staring at a stale route
  /// while we're fetching — better to skip a tick than to block the UI.
  late final Dio _directionsDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  // Refresh thresholds — same shape as the driver-side _NavigationMap.
  static const _routeRefreshMeters = 100.0;
  static const _routeRefreshThrottle = Duration(seconds: 30);

  // Captured once — pickup/destination don't change during an active ride.
  late final RideSearchState _searchState;

  @override
  void initState() {
    super.initState();
    _searchState = ref.read(rideSearchProvider);
  }

  @override
  void dispose() {
    _directionsDio.close(force: true);
    _mapboxMap = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RideRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Phase change (en-route → arrived → in-progress) flips the target
    // waypoint. Re-fetch the route + recenter the camera right away
    // instead of waiting for the next GPS fix to drag us out of sync.
    if (oldWidget.phase != widget.phase) {
      final pos = ref.read(liveDriverPositionProvider);
      if (pos != null) {
        _syncRoute(pos);
        _followCamera(pos);
      }
    }
  }

  /// Create or move the driver marker. No-op while the map isn't ready or
  /// the rider hasn't received the first fix yet — the next call (from
  /// either a socket update or the REST poller) takes care of it.
  ///
  /// Renders the driver as a 2-layer circle (white outer halo + gold inner
  /// dot) rather than a text emoji — the original 🚗 marker depended on the
  /// active Mapbox style shipping a colour-emoji font; on styles that don't
  /// (the default Streets v12 doesn't on all OS variants) the glyph
  /// silently rendered as a blank tofu box, which is the "marker never
  /// appears" symptom this widget was reported with.
  Future<void> _syncDriverMarker(LiveDriverPosition? pos) async {
    final manager = _driverCircleManager;
    if (manager == null) {
      developer.log(
          '[LIVE-TRACK] _syncDriverMarker bailed — circle manager not ready',
          name: 'RideRouteMap');
      return;
    }
    if (pos == null) {
      final halo = _driverHaloAnnotation;
      final dot = _driverDotAnnotation;
      if (halo != null) await manager.delete(halo);
      if (dot != null) await manager.delete(dot);
      _driverHaloAnnotation = null;
      _driverDotAnnotation = null;
      developer.log('[LIVE-TRACK] driver marker cleared (pos=null)',
          name: 'RideRouteMap');
      return;
    }
    final point = Point(
      coordinates: Position(pos.longitude, pos.latitude),
    );
    final halo = _driverHaloAnnotation;
    final dot = _driverDotAnnotation;
    if (halo == null || dot == null) {
      _driverHaloAnnotation = await manager.create(
        CircleAnnotationOptions(
          geometry: point,
          circleRadius: 14,
          circleColor: 0xFFFFFFFF,
          circleStrokeColor: 0x33000000,
          circleStrokeWidth: 1.0,
        ),
      );
      _driverDotAnnotation = await manager.create(
        CircleAnnotationOptions(
          geometry: point,
          circleRadius: 9,
          // primaryGold (0xFFF5A623) for visual consistency with the
          // route polyline.
          circleColor: 0xFFF5A623,
          circleStrokeColor: 0xFFFFFFFF,
          circleStrokeWidth: 2.0,
        ),
      );
      developer.log(
          '[LIVE-TRACK] driver marker CREATED at (${pos.latitude}, ${pos.longitude})',
          name: 'RideRouteMap');
    } else {
      halo.geometry = point;
      dot.geometry = point;
      await manager.update(halo);
      await manager.update(dot);
      developer.log(
          '[LIVE-TRACK] driver marker moved to (${pos.latitude}, ${pos.longitude})',
          name: 'RideRouteMap');
    }
  }

  /// The lat/lng the driver is currently navigating *to* — pickup until
  /// the trip starts, drop-off after. Returns null when the corresponding
  /// search-state coords are missing.
  Position? _targetForPhase(RideTrackingPhase phase) {
    final pickup = _searchState.pickup;
    final dest = _searchState.destination;
    switch (phase) {
      case RideTrackingPhase.inProgress:
      case RideTrackingPhase.completed:
        if (dest?.lat == null || dest?.lng == null) return null;
        return Position(dest!.lng!, dest.lat!);
      case RideTrackingPhase.enRoute:
      case RideTrackingPhase.arrived:
        if (pickup?.lat == null || pickup?.lng == null) return null;
        return Position(pickup!.lng!, pickup.lat!);
      case RideTrackingPhase.cancelled:
        // Tracking screen routes away the moment phase flips to cancelled,
        // so there's no useful target — null skips the route fetch and
        // we render whatever is already on the map for the single frame
        // before the navigation lands.
        return null;
    }
  }

  /// Fetch a driving route from the driver's current position to whatever
  /// waypoint matches the current phase, and draw it as a polyline. Skips
  /// the network call if the driver hasn't moved much since the last fetch
  /// (and the phase hasn't flipped).
  Future<void> _syncRoute(LiveDriverPosition? pos) async {
    final manager = _polylineManager;
    if (manager == null || pos == null) return;
    final origin = Position(pos.longitude, pos.latitude);
    final target = _targetForPhase(widget.phase);
    if (target == null) return;

    // Skip refetch if we already have a route that's still fresh.
    final last = _lastRoutedFromCoord;
    final phaseChanged = _lastRoutedPhase != widget.phase;
    if (last != null && !phaseChanged && _routeAnnotation != null) {
      final drift = _haversineMeters(last, origin);
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
      final coords = await _fetchMapboxRoute(origin, target);
      if (!mounted || coords == null || coords.length < 2) return;
      final geom = LineString(coordinates: coords);
      final existing = _routeAnnotation;
      if (existing == null) {
        _routeAnnotation = await manager.create(
          PolylineAnnotationOptions(
            geometry: geom,
            // 0xAARRGGBB — primaryGold-ish at full opacity.
            lineColor: 0xFFF5A623,
            lineWidth: 5.0,
          ),
        );
      } else {
        existing.geometry = geom;
        await manager.update(existing);
      }
      _lastRoutedFromCoord = origin;
      _lastRoutedPhase = widget.phase;
    } catch (e) {
      developer.log('Mapbox directions fetch failed: $e',
          name: 'RideRouteMap', level: 800);
    } finally {
      _routeFetchInFlight = false;
    }
  }

  /// Camera follow — keeps both the driver and the next waypoint in view
  /// as the driver moves. Same fitBounds approach as the static `_fitBounds`
  /// but with the driver's current position substituted for the static
  /// pickup point so the camera tracks the car.
  Future<void> _followCamera(LiveDriverPosition pos) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    final target = _targetForPhase(widget.phase);
    if (target == null) return;
    final driverCoord = Position(pos.longitude, pos.latitude);

    final minLat = math.min(driverCoord.lat.toDouble(), target.lat.toDouble());
    final maxLat = math.max(driverCoord.lat.toDouble(), target.lat.toDouble());
    final minLng = math.min(driverCoord.lng.toDouble(), target.lng.toDouble());
    final maxLng = math.max(driverCoord.lng.toDouble(), target.lng.toDouble());

    try {
      final camera = await mapboxMap.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(minLng, minLat)),
          northeast: Point(coordinates: Position(maxLng, maxLat)),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(top: 160, left: 60, bottom: 320, right: 60),
        null,
        null,
        null,
        null,
      );
      await mapboxMap.flyTo(
        camera,
        // Smooth 600ms slide so the camera glides between fixes rather
        // than jumping every update.
        null,
      );
    } catch (_) {
      // Camera moves are best-effort; failing one tick doesn't matter.
    }
  }

  /// Mapbox Directions API call. Returns the route's GeoJSON coordinates
  /// (already `[lng, lat]` in the right order for `LineString`). Returns
  /// null on any failure so the polyline path falls through to the static
  /// pickup/destination markers.
  Future<List<Position>?> _fetchMapboxRoute(
    Position origin,
    Position destination,
  ) async {
    final coords = '${origin.lng},${origin.lat};'
        '${destination.lng},${destination.lat}';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/driving/$coords',
      {
        'geometries': 'geojson',
        'overview': 'full',
        'access_token': MapboxConfig.accessToken,
      },
    );
    final response = await _directionsDio.getUri<Map<String, dynamic>>(uri);
    final data = response.data;
    if (data == null) return null;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>?;
    final raw = geometry?['coordinates'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) return null;
    return raw.map((c) {
      final pair = c as List<dynamic>;
      return Position(
        (pair[0] as num).toDouble(),
        (pair[1] as num).toDouble(),
      );
    }).toList(growable: false);
  }

  /// Great-circle distance in meters between two `Position` coordinates.
  /// Used to throttle Directions API calls — the rider's marker only
  /// triggers a route refetch when the driver has moved meaningfully.
  static double _haversineMeters(Position a, Position b) {
    const earthRadius = 6371000.0;
    final lat1 = a.lat.toDouble() * math.pi / 180.0;
    final lat2 = b.lat.toDouble() * math.pi / 180.0;
    final dLat = (b.lat.toDouble() - a.lat.toDouble()) * math.pi / 180.0;
    final dLng = (b.lng.toDouble() - a.lng.toDouble()) * math.pi / 180.0;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 + s2 * s2 * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    developer.log('[LIVE-TRACK] map created — wiring annotation managers',
        name: 'RideRouteMap');

    // Disable built-in compass and scale bar for a cleaner look.
    await mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
    await mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));

    // Manager creation order is the z-order: first-created is drawn first
    // (lowest layer). Route polyline at the bottom, pickup/destination
    // text markers above it, driver circle on top so the car never gets
    // hidden by the route line under it.
    _polylineManager =
        await mapboxMap.annotations.createPolylineAnnotationManager();
    _driverCircleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    await _addMarkers();
    await _fitBounds();
    // Pick up any driver fix that arrived before the map was ready —
    // marker, route, and camera all sync at once.
    final driverPos = ref.read(liveDriverPositionProvider);
    developer.log(
        '[LIVE-TRACK] map ready — initial driverPos=${driverPos != null ? "(${driverPos.latitude}, ${driverPos.longitude})" : "null"}',
        name: 'RideRouteMap');
    await _syncDriverMarker(driverPos);
    if (driverPos != null) {
      await _syncRoute(driverPos);
      await _followCamera(driverPos);
    }
  }

  Future<void> _addMarkers() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    _annotationManager ??=
        await mapboxMap.annotations.createPointAnnotationManager();

    await _annotationManager!.deleteAll();

    final pickup = _searchState.pickup;
    final dest = _searchState.destination;

    if (pickup?.lat != null && pickup?.lng != null) {
      await _annotationManager!.create(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(pickup!.lng!, pickup.lat!),
          ),
          textField: '📍',
          textSize: 24,
        ),
      );
    }

    if (dest?.lat != null && dest?.lng != null) {
      await _annotationManager!.create(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(dest!.lng!, dest.lat!),
          ),
          textField: '🏁',
          textSize: 24,
        ),
      );
    }
  }

  Future<void> _fitBounds() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    final pickup = _searchState.pickup;
    final dest = _searchState.destination;

    if (pickup?.lat == null || dest?.lat == null) return;

    final minLat = pickup!.lat! < dest!.lat! ? pickup.lat! : dest.lat!;
    final maxLat = pickup.lat! > dest.lat! ? pickup.lat! : dest.lat!;
    final minLng = pickup.lng! < dest.lng! ? pickup.lng! : dest.lng!;
    final maxLng = pickup.lng! > dest.lng! ? pickup.lng! : dest.lng!;

    final camera = await mapboxMap.cameraForCoordinateBounds(
      CoordinateBounds(
        southwest: Point(coordinates: Position(minLng, minLat)),
        northeast: Point(coordinates: Position(maxLng, maxLat)),
        infiniteBounds: false,
      ),
      MbxEdgeInsets(top: 120, left: 60, bottom: 320, right: 60),
      null,
      null,
      null,
      null,
    );
    await mapboxMap.setCamera(camera);
  }

  @override
  Widget build(BuildContext context) {
    // Re-sync the driver pin, the on-road route polyline, and the camera
    // every time the live position changes. Socket updates from
    // `core/providers/socket_provider.dart` and the tracking screen's
    // periodic REST hydrate both flow through `liveDriverPositionProvider`.
    ref.listen<LiveDriverPosition?>(liveDriverPositionProvider, (_, next) {
      developer.log(
          '[LIVE-TRACK] provider tick → ${next != null ? "(${next.latitude}, ${next.longitude})" : "null"}',
          name: 'RideRouteMap');
      _syncDriverMarker(next);
      if (next != null) {
        _syncRoute(next);
        _followCamera(next);
      }
    });

    final pickup = _searchState.pickup;
    final cachedDevice = ref.read(currentDevicePositionProvider);
    final initialCenter = pickup?.lat != null && pickup?.lng != null
        ? Position(pickup!.lng!, pickup.lat!)
        : (cachedDevice != null
            ? Position(cachedDevice.longitude, cachedDevice.latitude)
            : Position(MapboxConfig.defaultLng, MapboxConfig.defaultLat));

    final statusBarHeight = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        Positioned.fill(
          child: MapWidget(
            key: const ValueKey('rideRouteMap'),
            styleUri: MapboxConfig.styleUrl,
            cameraOptions: CameraOptions(
              center: Point(coordinates: initialCenter),
              zoom: 14.0,
            ),
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
        // Tracking screen navigates away on both terminal phases; render
        // the trip pill in the brief frame before that happens so we
        // don't flash an empty area.
        return _InProgressPill(minutes: widget.etaMinutes);
    }
  }
}

// ── Destination (HEADING TO) card ─────────────────────────────────────────────

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

/// Gold rail: filled dot → dashed vertical line → outlined circle.
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
