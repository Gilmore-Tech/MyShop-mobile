import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../../core/providers/socket_provider.dart';
import '../providers/active_job_provider.dart';

/// Mapbox-backed map for the active-job tracking screen.
///
/// Renders two pins: the job site (🛠) and, once the artisan goes online
/// for the job, the artisan's live position (👷). Live position arrives
/// over the `job:artisan:location` socket event (forwarded by the backend
/// from REST artisan-location heartbeats every ~4s) and is held in
/// [liveArtisanPositionProvider]. The widget joins the job room via
/// `client:track:job` on init and leaves via `client:untrack:job` on
/// dispose so events stop flowing once the screen unmounts.
class JobTrackingMap extends ConsumerStatefulWidget {
  final String jobId;
  final double? jobLat;
  final double? jobLng;

  const JobTrackingMap({
    super.key,
    required this.jobId,
    required this.jobLat,
    required this.jobLng,
  });

  @override
  ConsumerState<JobTrackingMap> createState() => _JobTrackingMapState();
}

class _JobTrackingMapState extends ConsumerState<JobTrackingMap> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _annotationManager;
  PointAnnotation? _jobAnnotation;
  PointAnnotation? _artisanAnnotation;

  @override
  void initState() {
    super.initState();
    // Subscribe to the job's tracking room so we receive live artisan
    // position emits. Setting `trackedJobIdProvider` lets the socket
    // bridge re-emit `client:track:job` on reconnect — a missed join
    // after a flap would otherwise silence the marker until next mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(trackedJobIdProvider.notifier).state = widget.jobId;
      try {
        ref.read(socketServiceProvider).emit(
          'client:track:job',
          {'jobId': widget.jobId},
        );
      } catch (_) {
        // Socket not connected yet; the connection bridge will re-emit
        // once it lands.
      }
    });
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
    await mapboxMap.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    _annotationManager =
        await mapboxMap.annotations.createPointAnnotationManager();
    await _syncJobMarker();
    await _syncArtisanMarker(ref.read(liveArtisanPositionProvider));
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

  Future<void> _syncArtisanMarker(LiveArtisanPosition? pos) async {
    final manager = _annotationManager;
    if (manager == null) return;
    if (pos == null || pos.jobId != widget.jobId) return;
    final point = Point(coordinates: Position(pos.longitude, pos.latitude));
    final existing = _artisanAnnotation;
    if (existing == null) {
      _artisanAnnotation = await manager.create(
        PointAnnotationOptions(
          geometry: point,
          textField: '👷',
          textSize: 28,
        ),
      );
    } else {
      existing.geometry = point;
      await manager.update(existing);
    }
  }

  @override
  void dispose() {
    // Best-effort tear-down — we don't await these because dispose runs
    // synchronously and the socket emit / state clear are fire-and-forget.
    try {
      ref.read(socketServiceProvider).emit(
        'client:untrack:job',
        {'jobId': widget.jobId},
      );
    } catch (_) {}
    try {
      ref.read(trackedJobIdProvider.notifier).state = null;
      ref.read(liveArtisanPositionProvider.notifier).state = null;
    } catch (_) {}
    _mapboxMap = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for live position fixes — `ref.listen` keeps the marker in
    // step with the socket without rebuilding the map widget itself.
    ref.listen<LiveArtisanPosition?>(liveArtisanPositionProvider,
        (_, next) => _syncArtisanMarker(next));

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
