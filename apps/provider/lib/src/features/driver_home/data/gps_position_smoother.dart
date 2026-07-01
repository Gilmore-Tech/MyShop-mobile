import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Accuracy-aware local filter for the driver's on-screen marker.
///
/// This replaces one paid Roads API request per GPS fix. It does not pretend
/// to know the road geometry; it only damps normal sensor jitter and rejects
/// implausible jumps when Android/iOS explicitly reports a poor fix.
class GpsPositionSmoother {
  LatLng? _lastPoint;
  DateTime? _lastTimestamp;

  LatLng filter({
    required LatLng point,
    required double accuracyMeters,
    required double speedMetersPerSecond,
    required DateTime timestamp,
  }) {
    final previous = _lastPoint;
    final previousTimestamp = _lastTimestamp;
    if (previous == null || previousTimestamp == null) {
      _remember(point, timestamp);
      return point;
    }

    final elapsedSeconds = timestamp
            .difference(previousTimestamp)
            .inMilliseconds
            .abs()
            .clamp(250, 10 * 1000) /
        1000.0;
    final distanceMeters = _haversineMeters(previous, point);
    final accuracy =
        accuracyMeters.isFinite && accuracyMeters >= 0 ? accuracyMeters : 100.0;
    final speed = speedMetersPerSecond.isFinite && speedMetersPerSecond >= 0
        ? speedMetersPerSecond
        : 0.0;

    // A low-quality fix that jumps much farther than the reported motion and
    // uncertainty permits is almost certainly a temporary GPS/cell handoff.
    final plausibleDistance = math.max(
      100.0,
      speed * elapsedSeconds * 3 + accuracy * 2,
    );
    if (accuracy > 50 && distanceMeters > plausibleDistance) {
      _lastTimestamp = timestamp;
      return previous;
    }

    final alpha = switch (accuracy) {
      <= 10 => 0.85,
      <= 25 => 0.65,
      <= 50 => 0.45,
      _ => 0.25,
    };
    final smoothed = LatLng(
      previous.latitude + (point.latitude - previous.latitude) * alpha,
      previous.longitude + (point.longitude - previous.longitude) * alpha,
    );
    _remember(smoothed, timestamp);
    return smoothed;
  }

  void reset() {
    _lastPoint = null;
    _lastTimestamp = null;
  }

  void _remember(LatLng point, DateTime timestamp) {
    _lastPoint = point;
    _lastTimestamp = timestamp;
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h =
        sinLat * sinLat + sinLng * sinLng * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }
}
