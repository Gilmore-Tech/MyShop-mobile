import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import 'current_location_provider.dart';

/// Reverse-geocoded label for the device's current position, used in the
/// home greeting and "Artisans" header. Falls back to the pilot-city label
/// when GPS is unavailable so the UI never shows a blank string.
final currentLocationLabelProvider = FutureProvider<String>((ref) async {
  const fallback = 'Kumasi, Ashanti Region';
  final position = await ref.watch(currentLocationServiceProvider).ensure();
  if (position == null) return fallback;
  final places = ref.watch(googlePlacesServiceProvider);
  final address = await places.reverseGeocode(
    position.latitude,
    position.longitude,
  );
  return address ?? fallback;
});
