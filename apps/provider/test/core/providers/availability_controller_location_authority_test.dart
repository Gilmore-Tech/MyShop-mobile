import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myshop_provider/src/core/providers/availability_controller.dart';

Position _position({
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
  final now = DateTime.utc(2026, 7, 17, 22);

  test('accepts a fix at the approved 30-second and 50-metre boundaries', () {
    expect(
      isOnlineLocationFixAcceptable(
        _position(
          timestamp: now.subtract(const Duration(seconds: 30)),
          accuracy: 50,
        ),
        now: now,
      ),
      isTrue,
    );
  });

  test('rejects a fix older than 30 seconds', () {
    expect(
      isOnlineLocationFixAcceptable(
        _position(timestamp: now.subtract(const Duration(seconds: 31))),
        now: now,
      ),
      isFalse,
    );
  });

  test('rejects a fix less accurate than 50 metres', () {
    expect(
      isOnlineLocationFixAcceptable(
        _position(timestamp: now, accuracy: 50.1),
        now: now,
      ),
      isFalse,
    );
  });

  test('rejects future-dated or invalid coordinate fixes', () {
    expect(
      isOnlineLocationFixAcceptable(
        _position(timestamp: now.add(const Duration(seconds: 1))),
        now: now,
      ),
      isFalse,
    );
    expect(
      isOnlineLocationFixAcceptable(
        _position(timestamp: now, latitude: 91),
        now: now,
      ),
      isFalse,
    );
  });

  test('online entry reuses an acceptable in-process fix', () async {
    final cached = _position(timestamp: now);
    var lastKnownCalled = false;
    var currentCalled = false;

    final resolved = await resolveOnlineEntryPosition(
      cached,
      now: now,
      lastKnownLoader: () async {
        lastKnownCalled = true;
        return null;
      },
      currentLoader: () async {
        currentCalled = true;
        return _position(timestamp: now);
      },
    );

    expect(resolved, same(cached));
    expect(lastKnownCalled, isFalse);
    expect(currentCalled, isFalse);
  });

  test('online entry safely reuses an acceptable OS last-known fix', () async {
    final lastKnown = _position(
      timestamp: now.subtract(const Duration(seconds: 20)),
      accuracy: 40,
    );
    var currentCalled = false;

    final resolved = await resolveOnlineEntryPosition(
      _position(timestamp: now.subtract(const Duration(minutes: 1))),
      now: now,
      lastKnownLoader: () async => lastKnown,
      currentLoader: () async {
        currentCalled = true;
        return _position(timestamp: now);
      },
    );

    expect(resolved, same(lastKnown));
    expect(currentCalled, isFalse);
  });

  test('online entry requests a fresh fix when cached fixes are unusable',
      () async {
    final fresh = _position(timestamp: now);

    final resolved = await resolveOnlineEntryPosition(
      _position(timestamp: now.subtract(const Duration(minutes: 1))),
      now: now,
      lastKnownLoader: () async => _position(
        timestamp: now,
        accuracy: 300,
      ),
      currentLoader: () async => fresh,
    );

    expect(resolved, same(fresh));
  });

  test('online entry still requests a fresh fix if last-known lookup throws',
      () async {
    final fresh = _position(timestamp: now);

    final resolved = await resolveOnlineEntryPosition(
      null,
      now: now,
      lastKnownLoader: () => Future<Position?>.error(StateError('unavailable')),
      currentLoader: () async => fresh,
    );

    expect(resolved, same(fresh));
  });
}
