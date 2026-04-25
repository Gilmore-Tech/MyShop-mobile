import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    show
        CameraOptions,
        CompassSettings,
        CoordinateBounds,
        MapWidget,
        MapboxMap,
        MbxEdgeInsets,
        PointAnnotation,
        PointAnnotationManager,
        PointAnnotationOptions,
        Point,
        Position,
        ScaleBarSettings;
import 'package:shared_ui/shared_ui.dart';

import '../../../core/constants/mapbox_config.dart';
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

  /// Separate annotation for the driver — kept around so we can update its
  /// geometry on each fix instead of tearing down and re-creating every
  /// pickup/destination marker as well.
  PointAnnotation? _driverAnnotation;

  // Captured once — pickup/destination don't change during an active ride.
  late final RideSearchState _searchState;

  @override
  void initState() {
    super.initState();
    _searchState = ref.read(rideSearchProvider);
  }

  @override
  void dispose() {
    _mapboxMap = null;
    super.dispose();
  }

  /// Create or move the driver marker. No-op while the map isn't ready or
  /// the rider hasn't received the first fix yet — the next call (from
  /// either a socket update or the REST poller) takes care of it.
  Future<void> _syncDriverMarker(LiveDriverPosition? pos) async {
    final manager = _annotationManager;
    if (manager == null) return;
    if (pos == null) {
      final existing = _driverAnnotation;
      if (existing != null) {
        await manager.delete(existing);
        _driverAnnotation = null;
      }
      return;
    }
    final point = Point(
      coordinates: Position(pos.longitude, pos.latitude),
    );
    final existing = _driverAnnotation;
    if (existing == null) {
      _driverAnnotation = await manager.create(
        PointAnnotationOptions(
          geometry: point,
          textField: '🚗',
          textSize: 26,
        ),
      );
    } else {
      existing.geometry = point;
      await manager.update(existing);
    }
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Disable built-in compass and scale bar for a cleaner look.
    await mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
    await mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));

    await _addMarkers();
    await _fitBounds();
    // Pick up any driver fix that arrived before the map was ready.
    await _syncDriverMarker(ref.read(liveDriverPositionProvider));
  }

  Future<void> _addMarkers() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    _annotationManager ??=
        await mapboxMap.annotations.createPointAnnotationManager();

    await _annotationManager!.deleteAll();

    final pickup = _searchState.pickup;
    final dest   = _searchState.destination;

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
    final dest   = _searchState.destination;

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
    // Re-sync the driver pin every time the live position changes — socket
    // updates from `core/providers/socket_provider.dart` and the REST
    // poller in `liveDriverPositionProvider`'s autoDispose stream both
    // route through here.
    ref.listen<LiveDriverPosition?>(liveDriverPositionProvider, (_, next) {
      _syncDriverMarker(next);
    });

    final pickup = _searchState.pickup;
    final initialCenter = pickup?.lat != null && pickup?.lng != null
        ? Position(pickup!.lng!, pickup.lat!)
        : Position(MapboxConfig.defaultLng, MapboxConfig.defaultLat);

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
        // Tracking screen navigates away on `completed`; render the trip
        // pill in the brief frame before that happens so we don't flash.
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
          const Icon(Icons.timer_outlined, size: 14, color: MyShopColors.textPrimary),
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
    const gap  = 3.0;
    final cx   = size.width / 2;
    double y   = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
