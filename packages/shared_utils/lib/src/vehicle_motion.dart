import 'dart:math' as math;

import 'geo_utils.dart';
import 'live_route_progress.dart';

class VehiclePose {
  const VehiclePose(this.point, this.heading);

  final RoutePoint point;
  final double heading;
}

/// Presentation only: interpolates received fixes, never invents future GPS.
/// Retargeting starts at the currently displayed pose, including mid-animation.
class VehicleMotion {
  VehiclePose? _from;
  VehiclePose? _to;
  DateTime? _startedAt;
  DateTime? _lastFixAt;
  DateTime? _lastReceivedAt;
  List<RoutePoint> _path = const [];
  List<double> _distances = const [];
  Duration duration = Duration.zero;

  bool update({
    required RoutePoint point,
    required DateTime now,
    DateTime? fixAt,
    double? heading,
    List<RoutePoint> route = const [],
  }) {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180) return false;
    final previousTimestamp = _lastFixAt;
    if (fixAt != null &&
        previousTimestamp != null &&
        !fixAt.isAfter(previousTimestamp)) {
      return false;
    }
    final current = sample(now);
    final elapsed = fixAt != null && previousTimestamp != null
        ? fixAt.difference(previousTimestamp)
        : _lastReceivedAt == null
            ? const Duration(seconds: 4)
            : now.difference(_lastReceivedAt!);
    final distance = current == null ? 0.0 : _distance(current.point, point);
    final targetHeading = heading != null && heading.isFinite && heading >= 0
        ? heading % 360
        : current == null || distance < 2
            ? current?.heading ?? 0
            : _bearing(current.point, point);
    _lastFixAt = fixAt ?? _lastFixAt;
    _lastReceivedAt = now;
    _startedAt = now;
    _from = current ?? VehiclePose(point, targetHeading);
    // Ignore stationary compass noise; it must not spin a parked car.
    _to = VehiclePose(
      point,
      current != null && distance < 1 ? current.heading : targetHeading,
    );
    // Reconnects and implausible jumps are recovery fixes, not a journey to
    // animate across the city. No extrapolation when a stream stops arriving.
    duration = current == null || elapsed.inSeconds > 15 || distance > 750
        ? Duration.zero
        : Duration(milliseconds: elapsed.inMilliseconds.clamp(350, 5000));
    _path = _roadPath(_from!.point, point, route);
    if ((heading == null || !heading.isFinite || heading < 0) &&
        _path.length > 2 &&
        distance >= 2) {
      for (var i = _path.length - 1; i > 0; i--) {
        if (_distance(_path[i - 1], _path[i]) > 0.5) {
          _to = VehiclePose(point, _bearing(_path[i - 1], _path[i]));
          break;
        }
      }
    }
    _distances = [0];
    for (var i = 1; i < _path.length; i++) {
      _distances.add(_distances.last + _distance(_path[i - 1], _path[i]));
    }
    return true;
  }

  VehiclePose? sample(DateTime now) {
    final from = _from;
    final to = _to;
    if (from == null || to == null || _startedAt == null) return null;
    if (duration == Duration.zero) return to;
    final t =
        (now.difference(_startedAt!).inMicroseconds / duration.inMicroseconds)
            .clamp(0.0, 1.0);
    if (t >= 1) return to;
    final length = _distances.last;
    final along = length * t;
    var rotation = _angle(from.heading, to.heading, t);
    if (_path.length > 2 && length > 2) {
      // Look either side of a bend so orientation changes through the turn
      // instead of rotating abruptly when crossing a polyline vertex.
      final tangent = _bearing(
        _pointAt((along - 6).clamp(0, length).toDouble()),
        _pointAt((along + 6).clamp(0, length).toDouble()),
      );
      rotation = _angle(from.heading, tangent, (t * 5).clamp(0, 1));
      if (t > 0.8) rotation = _angle(rotation, to.heading, (t - 0.8) * 5);
    }
    return VehiclePose(_pointAt(along), rotation);
  }

  RoutePoint _pointAt(double distance) {
    for (var i = 1; i < _path.length; i++) {
      if (distance <= _distances[i]) {
        final length = _distances[i] - _distances[i - 1];
        return _lerp(
          _path[i - 1],
          _path[i],
          length <= 0 ? 0 : (distance - _distances[i - 1]) / length,
        );
      }
    }
    return _path.last;
  }

  void reset() {
    _from = null;
    _to = null;
    _lastFixAt = null;
    _lastReceivedAt = null;
    _startedAt = null;
    _path = const [];
    _distances = const [];
    duration = Duration.zero;
  }

  static List<RoutePoint> _roadPath(
    RoutePoint from,
    RoutePoint to,
    List<RoutePoint> route,
  ) {
    if (route.length < 2) return [from, to];
    final start = _project(from, route);
    final end = _project(to, route);
    // Never force a real deviation, U-turn or parallel road onto an old route.
    if (start.offset > 35 || end.offset > 35 || end.along <= start.along) {
      return [from, to];
    }
    if (end.along - start.along > _distance(from, to) * 3 + 30) {
      return [from, to];
    }
    return [
      from,
      start.point,
      for (var i = start.segment + 1; i <= end.segment; i++) route[i],
      end.point,
      to,
    ];
  }

  static ({RoutePoint point, int segment, double offset, double along})
      _project(RoutePoint point, List<RoutePoint> route) {
    var best =
        (point: route.first, segment: 0, offset: double.infinity, along: 0.0);
    var cumulative = 0.0;
    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final scale = math.cos(a.latitude * math.pi / 180);
      final dx = (b.longitude - a.longitude) * scale;
      final dy = b.latitude - a.latitude;
      final px = (point.longitude - a.longitude) * scale;
      final py = point.latitude - a.latitude;
      final squared = dx * dx + dy * dy;
      final t =
          squared == 0 ? 0.0 : ((px * dx + py * dy) / squared).clamp(0.0, 1.0);
      final projected = _lerp(a, b, t);
      final offset = _distance(point, projected);
      final length = _distance(a, b);
      if (offset < best.offset) {
        best = (
          point: projected,
          segment: i,
          offset: offset,
          along: cumulative + length * t
        );
      }
      cumulative += length;
    }
    return best;
  }

  static double _distance(RoutePoint a, RoutePoint b) =>
      haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  static RoutePoint _lerp(RoutePoint a, RoutePoint b, double t) => (
        latitude: a.latitude + (b.latitude - a.latitude) * t,
        longitude: a.longitude + (b.longitude - a.longitude) * t,
      );

  static double _angle(double a, double b, double t) =>
      (a + ((b - a + 540) % 360 - 180) * t) % 360;

  static double _bearing(RoutePoint a, RoutePoint b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final lng = (b.longitude - a.longitude) * math.pi / 180;
    return (math.atan2(
                  math.sin(lng) * math.cos(lat2),
                  math.cos(lat1) * math.sin(lat2) -
                      math.sin(lat1) * math.cos(lat2) * math.cos(lng),
                ) *
                180 /
                math.pi +
            360) %
        360;
  }
}
