import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/google_places_service.dart';
import 'current_location_provider.dart';

/// Structured current-location label used when seeding a ride pickup.
final currentLocationPlaceProvider =
    FutureProvider<ReverseGeocodePlace>((ref) async {
  const fallback = ReverseGeocodePlace(
    name: 'Current location',
    address: 'Kumasi, Ashanti Region',
  );
  final position = await ref.watch(currentLocationServiceProvider).ensure();
  if (position == null) return fallback;
  final places = ref.watch(googlePlacesServiceProvider);
  return await places.reverseGeocodePlace(
        position.latitude,
        position.longitude,
      ) ??
      fallback;
});

/// Reverse-geocoded label for the device's current position, used in the
/// home greeting and "Artisans" header. Falls back to the pilot-city label
/// when GPS is unavailable so the UI never shows a blank string.
final currentLocationLabelProvider = FutureProvider<String>((ref) async {
  return (await ref.watch(currentLocationPlaceProvider.future)).name;
});
