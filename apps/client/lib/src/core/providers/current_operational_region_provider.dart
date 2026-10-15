import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../di/providers.dart';
import 'current_location_provider.dart';

const operationalAreaUnavailableTitle =
    'Your current location is outside our service area';
const operationalAreaUnavailableMessage =
    'You can still explore MyShop and choose a different pickup or job '
    'location. We will confirm availability for the selected location before '
    'you book.';

/// A service-area warning is authoritative only when it is based on a live,
/// reasonably precise fix from this app session. A last-known position remains
/// useful for quickly centring maps, but must not classify the rider's current
/// operational region.
const operationalRegionMaximumPositionAge = Duration(minutes: 2);
const operationalRegionMaximumAccuracyMetres = 250.0;

bool isPositionReliableForOperationalRegion(Position? position) {
  return isUsableDevicePosition(
    position,
    maximumAge: operationalRegionMaximumPositionAge,
    maximumAccuracyMetres: operationalRegionMaximumAccuracyMetres,
  );
}

/// Resolves the client's physical operational region from the shared device
/// fix. Service availability comes from the returned region flags; the
/// resolution itself is deliberately service-neutral so a ride-only region is
/// not mistaken for being outside the platform when jobs are disabled there.
final currentOperationalRegionProvider = FutureProvider<Region?>((ref) async {
  final position = ref.watch(freshCurrentDevicePositionProvider);
  if (!isPositionReliableForOperationalRegion(position)) return null;

  return ref.watch(regionServiceProvider).resolveCurrentRegion(
        latitude: position!.latitude,
        longitude: position.longitude,
        // Kept for compatibility with older API deployments. Current servers
        // resolve the physical region first and return both service flags.
        service: 'rides',
      );
});
