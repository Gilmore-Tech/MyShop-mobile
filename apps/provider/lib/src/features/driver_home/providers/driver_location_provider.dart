import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/providers/provider_status_provider.dart';

/// Streams the driver's current [Position] only while they are online (or busy
/// on an active ride). When the driver toggles offline, the provider auto-
/// disposes the underlying location stream so we stop draining the battery.
///
/// Consumers (e.g. the home screen map) listen to this and update the car
/// marker on each emission.
final driverLocationStreamProvider =
    StreamProvider.autoDispose<Position>((ref) async* {
  final status = ref.watch(providerStatusProvider);
  if (status.isOffline) {
    debugPrint('[LOC] stream provider: offline — not subscribing');
    return;
  }
  debugPrint('[LOC] stream provider: online — checking permission');

  // Make sure we have permission before subscribing.
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    debugPrint('[LOC] stream provider: permission $permission — bailing');
    return;
  }

  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    debugPrint('[LOC] stream provider: services disabled — bailing');
    return;
  }

  // Try the OS-cached fix first so the bridge fires immediately rather than
  // waiting on a fresh GPS lock (which on iOS can fail with kCLErrorDomain 0
  // until the sensor settles).
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      debugPrint('[LOC] stream provider: yielding last-known '
          '(${last.latitude}, ${last.longitude})');
      yield last;
    }
  } catch (e) {
    debugPrint('[LOC] stream provider: getLastKnownPosition failed: $e');
  }

  // Emit the current fix immediately so the marker appears without waiting
  // for the first stream tick.
  try {
    final initial = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
    debugPrint('[LOC] stream provider: yielding fresh '
        '(${initial.latitude}, ${initial.longitude})');
    yield initial;
  } catch (e) {
    debugPrint('[LOC] stream provider: getCurrentPosition failed: $e — '
        'continuing to position stream');
  }

  // 1m distance filter — fine enough that the driver marker + camera
  // follow appear continuous during a live ride, the way Google Maps
  // "Start" mode does. 5m felt choppy on slower urban segments (the
  // marker would freeze for several seconds at a time). Battery cost
  // is bounded by `LocationAccuracy.high` already issuing a single
  // hardware request — the filter is a software gate on emission rate,
  // not the GPS duty cycle.
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    ),
  );
});
