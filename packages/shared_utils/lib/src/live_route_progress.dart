import 'dart:math' as math;

import 'geo_utils.dart';

typedef RoutePoint = ({double latitude, double longitude});

/// Remaining road distance and traffic-weighted travel time at one GPS fix.
class LiveRouteProgress {
  const LiveRouteProgress({
    required this.remainingMeters,
    required this.remainingSeconds,
    required this.offRouteMeters,
  });

  final double remainingMeters;
  final double remainingSeconds;
  final double offRouteMeters;

  // Do not claim arrival solely from a rounded ETA; ride status owns arrival.
  int get etaMinutes => math.max(1, (remainingSeconds / 60).ceil());
}

/// Projects GPS onto a road polyline, then measures the road still ahead.
/// Duration is weighted by the remaining fraction of the traffic-aware route.
/// It is never decremented merely because wall-clock time has passed.
class LiveRoute {
  LiveRoute({
    required List<RoutePoint> points,
    required this.distanceMeters,
    required this.durationSeconds,
  }) : points = List.unmodifiable(points) {
    _cumulative = [0];
    for (var i = 1; i < points.length; i++) {
      final segmentMeters = haversineMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
      _cumulative.add(_cumulative.last + segmentMeters);
    }
  }

  final List<RoutePoint> points;
  final double distanceMeters;
  final double durationSeconds;
  late final List<double> _cumulative;

  LiveRouteProgress? progressAt(RoutePoint driver) {
    if (points.length < 2 ||
        _cumulative.last <= 0 ||
        durationSeconds <= 0 ||
        distanceMeters <= 0 ||
        !driver.latitude.isFinite ||
        !driver.longitude.isFinite) {
      return null;
    }
    var nearest = double.infinity;
    var along = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final lngScale = 111320 * math.cos(a.latitude * math.pi / 180);
      final bx = (b.longitude - a.longitude) * lngScale;
      final by = (b.latitude - a.latitude) * 111320;
      final px = (driver.longitude - a.longitude) * lngScale;
      final py = (driver.latitude - a.latitude) * 111320;
      final lengthSquared = bx * bx + by * by;
      final fraction = lengthSquared == 0
          ? 0.0
          : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
      final dx = px - fraction * bx;
      final dy = py - fraction * by;
      final offset = math.sqrt(dx * dx + dy * dy);
      if (offset < nearest) {
        nearest = offset;
        along =
            _cumulative[i] + fraction * (_cumulative[i + 1] - _cumulative[i]);
      }
    }
    final remainingFraction = (1 - along / _cumulative.last).clamp(0.0, 1.0);
    return LiveRouteProgress(
      remainingMeters: distanceMeters * remainingFraction,
      remainingSeconds: durationSeconds * remainingFraction,
      offRouteMeters: nearest,
    );
  }
}
