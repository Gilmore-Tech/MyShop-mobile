import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myshop_provider/src/core/services/lifecycle_location_service.dart';

Position position({
  required DateTime timestamp,
  double accuracy = 10,
  double latitude = 6.6885,
  double longitude = -1.6244,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  final now = DateTime.utc(2026, 7, 19, 3);

  test('accepts the approved inclusive 15-second and 30-metre boundaries', () {
    expect(
      isLifecycleLocationFixAcceptable(
        position(
          timestamp: now.subtract(const Duration(seconds: 15)),
          accuracy: 30,
        ),
        now: now,
      ),
      isTrue,
    );
  });

  test('rejects stale, future, inaccurate, and invalid-coordinate fixes', () {
    expect(
      isLifecycleLocationFixAcceptable(
        position(timestamp: now.subtract(const Duration(milliseconds: 15001))),
        now: now,
      ),
      isFalse,
    );
    expect(
      isLifecycleLocationFixAcceptable(
        position(timestamp: now.add(const Duration(milliseconds: 1))),
        now: now,
      ),
      isFalse,
    );
    expect(
      isLifecycleLocationFixAcceptable(
        position(timestamp: now, accuracy: 30.01),
        now: now,
      ),
      isFalse,
    );
    expect(
      isLifecycleLocationFixAcceptable(
        position(timestamp: now, latitude: 91),
        now: now,
      ),
      isFalse,
    );
  });

  test('reuses an acceptable cached fix without another GPS request', () async {
    var loads = 0;
    final cached = position(timestamp: now);
    final service = LifecycleLocationService(
      clock: () => now,
      currentPositionLoader: () async {
        loads += 1;
        return position(timestamp: now);
      },
    );

    await expectLater(service.obtain(cached), completion(same(cached)));
    expect(loads, 0);
  });

  test('replaces a stale cache with a fresh high-accuracy fix', () async {
    final fresh = position(timestamp: now, accuracy: 8);
    final service = LifecycleLocationService(
      clock: () => now,
      currentPositionLoader: () async => fresh,
    );

    await expectLater(
      service.obtain(
        position(timestamp: now.subtract(const Duration(minutes: 1))),
      ),
      completion(same(fresh)),
    );
  });

  test('reports stable failures for unavailable and inaccurate fresh GPS',
      () async {
    final unavailable = LifecycleLocationService(
      clock: () => now,
      currentPositionLoader: () async => throw Exception('gps unavailable'),
    );
    await expectLater(
      unavailable.obtain(null),
      throwsA(
        isA<LifecycleLocationException>().having(
          (error) => error.code,
          'code',
          'LIFECYCLE_LOCATION_REQUIRED',
        ),
      ),
    );

    final inaccurate = LifecycleLocationService(
      clock: () => now,
      currentPositionLoader: () async => position(timestamp: now, accuracy: 31),
    );
    await expectLater(
      inaccurate.obtain(null),
      throwsA(
        isA<LifecycleLocationException>().having(
          (error) => error.code,
          'code',
          'GPS_ACCURACY_REQUIRED',
        ),
      ),
    );
  });
}
