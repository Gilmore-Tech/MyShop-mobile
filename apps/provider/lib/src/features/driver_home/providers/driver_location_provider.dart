import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/providers/provider_status_provider.dart';

typedef OnlinePositionLoader = Future<Position> Function();
typedef LastKnownPositionLoader = Future<Position?> Function();

/// A 10-second acquisition threshold leaves enough time for the 15-second
/// durable writer and network latency while the server enforces its strict
/// 30-second dispatch boundary.
const Duration periodicOnlineFixMaxAge = Duration(seconds: 10);
const Duration onlineEntryFixTimeout = Duration(seconds: 20);

/// Entering the matching pool is an explicit user action and can tolerate a
/// longer cold-start wait than the periodic writer. Eight seconds proved too
/// short on real Android hardware indoors even with every permission granted.
final onlineEntryPositionLoaderProvider = Provider<OnlinePositionLoader>((_) {
  return () => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: onlineEntryFixTimeout,
        ),
      );
});

final lastKnownPositionLoaderProvider =
    Provider<LastKnownPositionLoader>((_) => Geolocator.getLastKnownPosition);

final onlinePositionLoaderProvider = Provider<OnlinePositionLoader>((_) {
  return () => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
});

bool periodicOnlineFixRefreshRequired(
  Position? position, {
  DateTime? now,
}) {
  if (position == null) return true;
  final age = (now ?? DateTime.now()).toUtc().difference(
        position.timestamp.toUtc(),
      );
  return age.isNegative || age > periodicOnlineFixMaxAge;
}

Future<Position> resolvePeriodicOnlinePosition(
  Position? position, {
  required OnlinePositionLoader loader,
  DateTime? now,
}) {
  if (!periodicOnlineFixRefreshRequired(position, now: now)) {
    return Future<Position>.value(position!);
  }
  return loader();
}

LocationSettings onlineStreamLocationSettings(TargetPlatform platform) {
  if (platform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      // Matching requires a genuinely new device fix every 30 seconds. A
      // positive distance filter can suppress updates indefinitely while the
      // driver is stationary; replaying that old sample as a heartbeat cannot
      // truthfully refresh its capture timestamp. Request periodic fixes even
      // at zero movement and let the REST writer retain its 15-second cadence.
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 4),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'MyShop Provider is online',
        notificationText: 'Keeping your location active for jobs and trips.',
        notificationChannelName: 'Provider location',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );
  }

  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 0,
  );
}

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
      debugPrint('[LOC] stream provider: yielding last-known location fix');
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
    debugPrint('[LOC] stream provider: yielding fresh location fix');
    yield initial;
  } catch (e) {
    debugPrint('[LOC] stream provider: getCurrentPosition failed: $e — '
        'continuing to position stream');
  }

  // A zero distance filter is intentional: an idle online driver must still
  // receive newly captured fixes. The server rejects replayed timestamps and
  // dispatch requires a fix no older than 30 seconds. Battery/network cost is
  // bounded by platform cadence and the separate 15-second REST writer. On
  // Android the foreground notification keeps the stream prioritized while
  // backgrounded; on iOS Background Modes + Always permission cover lock.
  yield* Geolocator.getPositionStream(
    locationSettings: onlineStreamLocationSettings(defaultTargetPlatform),
  );
});
