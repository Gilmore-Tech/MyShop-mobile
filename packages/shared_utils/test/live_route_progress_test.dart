import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  // U-shaped road: the destination is close across a barrier, but driving
  // there requires following the full road around it.
  final route = LiveRoute(
    points: const [
      (latitude: 0, longitude: 0),
      (latitude: 0, longitude: 0.01),
      (latitude: 0.01, longitude: 0.01),
      (latitude: 0.01, longitude: 0),
    ],
    distanceMeters: 3300,
    durationSeconds: 900,
  );
  test('uses remaining road length instead of distance across the barrier', () {
    final start = route.progressAt((latitude: 0, longitude: 0))!;
    final corner = route.progressAt((latitude: 0, longitude: 0.01))!;
    expect(start.etaMinutes, 15);
    expect(start.remainingMeters, 3300);
    expect(corner.remainingSeconds, closeTo(600, 1));
    expect(corner.remainingMeters, closeTo(2200, 1));
    expect(corner.remainingSeconds, lessThan(start.remainingSeconds));
  });
  test('ETA can increase when travelling away from the destination', () {
    final ahead = route.progressAt((latitude: 0.005, longitude: 0.01))!;
    final back = route.progressAt((latitude: 0, longitude: 0.005))!;
    expect(back.remainingSeconds, greaterThan(ahead.remainingSeconds));
  });
  test('stationary fixes do not simulate time progress', () {
    final first = route.progressAt((latitude: 0, longitude: 0.005))!;
    final next = route.progressAt((latitude: 0, longitude: 0.005))!;
    expect(next.remainingSeconds, first.remainingSeconds);
  });
  test('traffic refresh changes ETA without requiring movement', () {
    final slower = LiveRoute(
        points: route.points, distanceMeters: 3300, durationSeconds: 1800);
    const position = (latitude: 0.0, longitude: 0.005);
    expect(slower.progressAt(position)!.remainingSeconds,
        closeTo(route.progressAt(position)!.remainingSeconds * 2, 0.01));
  });
  test('reports deviations so apps reroute instead of claiming early arrival',
      () {
    final progress = route.progressAt((latitude: 0.005, longitude: 0.005))!;
    expect(progress.offRouteMeters, greaterThan(65));
  });
  test('does not declare arrival from rounded minutes', () {
    final atEnd = route.progressAt((latitude: 0.01, longitude: 0))!;
    expect(atEnd.remainingSeconds, 0);
    expect(atEnd.etaMinutes, 1);
  });
  test('unusable road routes cannot produce a plausible ETA', () {
    final invalid = LiveRoute(
        points: route.points, distanceMeters: 3300, durationSeconds: 0);
    expect(invalid.progressAt((latitude: 0, longitude: 0)), isNull);
    final empty = LiveRoute(points: [], distanceMeters: 0, durationSeconds: 0);
    expect(empty.progressAt((latitude: 0, longitude: 0)), isNull);
  });
}
