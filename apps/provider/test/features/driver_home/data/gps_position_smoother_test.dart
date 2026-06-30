import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myshop_provider/src/features/driver_home/data/gps_position_smoother.dart';

void main() {
  final start = DateTime.utc(2026, 6, 29, 12);

  test('accepts the first GPS fix exactly', () {
    final smoother = GpsPositionSmoother();
    const point = LatLng(6.6885, -1.6244);

    final result = smoother.filter(
      point: point,
      accuracyMeters: 8,
      speedMetersPerSecond: 0,
      timestamp: start,
    );

    expect(result, point);
  });

  test('damps normal GPS jitter according to reported accuracy', () {
    final smoother = GpsPositionSmoother();
    smoother.filter(
      point: const LatLng(6.6885, -1.6244),
      accuracyMeters: 8,
      speedMetersPerSecond: 4,
      timestamp: start,
    );

    final result = smoother.filter(
      point: const LatLng(6.6895, -1.6234),
      accuracyMeters: 20,
      speedMetersPerSecond: 4,
      timestamp: start.add(const Duration(seconds: 2)),
    );

    expect(result.latitude, closeTo(6.68915, 0.0000001));
    expect(result.longitude, closeTo(-1.62375, 0.0000001));
  });

  test('rejects a large jump when the OS reports a poor fix', () {
    final smoother = GpsPositionSmoother();
    const initial = LatLng(6.6885, -1.6244);
    smoother.filter(
      point: initial,
      accuracyMeters: 8,
      speedMetersPerSecond: 0,
      timestamp: start,
    );

    final result = smoother.filter(
      point: const LatLng(6.8, -1.4),
      accuracyMeters: 80,
      speedMetersPerSecond: 2,
      timestamp: start.add(const Duration(seconds: 2)),
    );

    expect(result, initial);
  });

  test('reset lets a new online session start from its current fix', () {
    final smoother = GpsPositionSmoother();
    smoother.filter(
      point: const LatLng(6.6885, -1.6244),
      accuracyMeters: 8,
      speedMetersPerSecond: 0,
      timestamp: start,
    );
    smoother.reset();
    const newSessionPoint = LatLng(6.71, -1.6);

    final result = smoother.filter(
      point: newSessionPoint,
      accuracyMeters: 10,
      speedMetersPerSecond: 0,
      timestamp: start.add(const Duration(minutes: 5)),
    );

    expect(result, newSessionPoint);
  });
}
