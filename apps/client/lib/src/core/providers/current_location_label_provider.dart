import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/google_places_service.dart';
import 'current_location_provider.dart';

/// Structured current-location label used when seeding a ride pickup.
final currentLocationPlaceProvider =
    FutureProvider<ReverseGeocodePlace>((ref) async {
  const fallback = ReverseGeocodePlace(
    name: 'Current location',
    address: 'Waiting for GPS signal',
  );
  var position = ref.watch(currentDevicePositionProvider);

  try {
    position ??= await ref.watch(currentLocationServiceProvider).ensure();
  } catch (error) {
    debugLog(() => '[LOC] current-location GPS lookup failed: $error');
  }

  if (position == null) return fallback;

  try {
    final places = ref.watch(googlePlacesServiceProvider);
    return await places.reverseGeocodePlace(
          position.latitude,
          position.longitude,
        ) ??
        _gpsFallback(position.latitude, position.longitude);
  } catch (error) {
    debugLog(() => '[LOC] current-location label failed: $error');
    return _gpsFallback(position.latitude, position.longitude);
  }
});

ReverseGeocodePlace _gpsFallback(double latitude, double longitude) {
  return ReverseGeocodePlace(
    name: 'Using GPS location',
    address: '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
  );
}

/// Reverse-geocoded label for the device's current position, used in the
/// home greeting and "Artisans" header. Falls back to a GPS/permission status
/// label when the backend cannot reverse-geocode the coordinate yet.
final currentLocationLabelProvider = FutureProvider<String>((ref) async {
  return (await ref.watch(currentLocationPlaceProvider.future)).name;
});
