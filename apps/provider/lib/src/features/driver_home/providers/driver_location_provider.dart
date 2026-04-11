import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'driver_status_provider.dart';

/// Streams the driver's current [Position] only while they are online (or busy
/// on an active ride). When the driver toggles offline, the provider auto-
/// disposes the underlying location stream so we stop draining the battery.
///
/// Consumers (e.g. the home screen map) listen to this and update the car
/// marker on each emission.
final driverLocationStreamProvider =
    StreamProvider.autoDispose<Position>((ref) async* {
  final status = ref.watch(driverStatusProvider);
  if (status.isOffline) return;

  // Make sure we have permission before subscribing.
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return;

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return;
  }

  // Emit the current fix immediately so the marker appears without waiting
  // for the first stream tick.
  try {
    final initial = await Geolocator.getCurrentPosition();
    yield initial;
  } catch (_) {
    // ignore — the stream below will deliver the first real fix
  }

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  );
});
