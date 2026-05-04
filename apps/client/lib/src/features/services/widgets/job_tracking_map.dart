import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    show
        CameraOptions,
        CompassSettings,
        MapWidget,
        MapboxMap,
        PointAnnotation,
        PointAnnotationManager,
        PointAnnotationOptions,
        Point,
        Position,
        ScaleBarSettings;

import '../../../core/constants/mapbox_config.dart';

/// Mapbox-backed map for the active-job tracking screen.
///
/// Renders the job site as a pin and centres the camera on it. Live artisan
/// position over WS isn't wired yet — the only signal currently available
/// is `GET /jobs/:id/bids/locations`, which the backend stops populating
/// once a bid is selected. When the backend ships an `artisan:location`
/// event for assigned jobs, drop the second marker in here using the same
/// pattern as `RideRouteMap._syncDriverMarker`.
class JobTrackingMap extends StatefulWidget {
  final double? jobLat;
  final double? jobLng;

  const JobTrackingMap({
    super.key,
    required this.jobLat,
    required this.jobLng,
  });

  @override
  State<JobTrackingMap> createState() => _JobTrackingMapState();
}

class _JobTrackingMapState extends State<JobTrackingMap> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _annotationManager;
  PointAnnotation? _jobAnnotation;

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
    await mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    _annotationManager =
        await mapboxMap.annotations.createPointAnnotationManager();
    await _syncJobMarker();
  }

  @override
  void didUpdateWidget(covariant JobTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobLat != widget.jobLat ||
        oldWidget.jobLng != widget.jobLng) {
      _syncJobMarker();
    }
  }

  Future<void> _syncJobMarker() async {
    final manager = _annotationManager;
    if (manager == null) return;
    final lat = widget.jobLat;
    final lng = widget.jobLng;
    if (lat == null || lng == null) return;
    final point = Point(coordinates: Position(lng, lat));
    final existing = _jobAnnotation;
    if (existing == null) {
      _jobAnnotation = await manager.create(
        PointAnnotationOptions(
          geometry: point,
          textField: '🛠',
          textSize: 28,
        ),
      );
    } else {
      existing.geometry = point;
      await manager.update(existing);
    }
    await _mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: 15.0,
      ),
      null,
    );
  }

  @override
  void dispose() {
    _mapboxMap = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.jobLat ?? MapboxConfig.defaultLat;
    final lng = widget.jobLng ?? MapboxConfig.defaultLng;
    return MapWidget(
      key: const ValueKey('jobTrackingMap'),
      styleUri: MapboxConfig.styleUrl,
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: 14.0,
      ),
      onMapCreated: _onMapCreated,
    );
  }
}
