import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

const lifecycleLocationFreshness = Duration(seconds: 15);
const lifecycleLocationMaxAccuracyMeters = 30.0;

typedef CurrentPositionLoader = Future<Position> Function();

class LifecycleLocationException implements Exception {
  const LifecycleLocationException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

bool isLifecycleLocationFixAcceptable(
  Position position, {
  DateTime? now,
}) {
  final clock = (now ?? DateTime.now()).toUtc();
  final capturedAt = position.timestamp.toUtc();
  final age = clock.difference(capturedAt);
  return position.latitude.isFinite &&
      position.latitude >= -90 &&
      position.latitude <= 90 &&
      position.longitude.isFinite &&
      position.longitude >= -180 &&
      position.longitude <= 180 &&
      position.accuracy.isFinite &&
      position.accuracy >= 0 &&
      position.accuracy <= lifecycleLocationMaxAccuracyMeters &&
      !age.isNegative &&
      age <= lifecycleLocationFreshness;
}

class LifecycleLocationService {
  LifecycleLocationService({
    CurrentPositionLoader? currentPositionLoader,
    DateTime Function()? clock,
  })  : _currentPositionLoader = currentPositionLoader ?? _loadCurrentPosition,
        _clock = clock ?? DateTime.now;

  final CurrentPositionLoader _currentPositionLoader;
  final DateTime Function() _clock;

  Future<Position> obtain(Position? cached) async {
    final now = _clock().toUtc();
    if (cached != null && isLifecycleLocationFixAcceptable(cached, now: now)) {
      return cached;
    }

    Position fresh;
    try {
      fresh = await _currentPositionLoader();
    } catch (_) {
      throw const LifecycleLocationException(
        'LIFECYCLE_LOCATION_REQUIRED',
        'MyShop could not get your current location. Check GPS and try again.',
      );
    }
    if (!fresh.accuracy.isFinite ||
        fresh.accuracy < 0 ||
        fresh.accuracy > lifecycleLocationMaxAccuracyMeters) {
      throw const LifecycleLocationException(
        'GPS_ACCURACY_REQUIRED',
        'GPS accuracy is too low. Move to an open area and wait for a better fix.',
      );
    }
    if (!isLifecycleLocationFixAcceptable(fresh, now: _clock().toUtc())) {
      throw const LifecycleLocationException(
        'GPS_FIX_STALE',
        'MyShop needs a GPS fix from the last 15 seconds. Try again.',
      );
    }
    return fresh;
  }

  static Future<Position> _loadCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
  }
}

final lifecycleLocationServiceProvider = Provider<LifecycleLocationService>(
  (_) => LifecycleLocationService(),
);
