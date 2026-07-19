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
}
