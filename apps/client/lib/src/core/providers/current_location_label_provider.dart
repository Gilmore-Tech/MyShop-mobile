import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/google_places_service.dart';
import 'current_location_provider.dart';

const _reverseGeocodeRetryDelays = <Duration>[
  Duration(milliseconds: 250),
  Duration(milliseconds: 750),
];

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
    debugPrint('[LOC] current-location GPS lookup failed: $error');
  }

  if (position == null) return fallback;

  final places = ref.watch(googlePlacesServiceProvider);
  final place = await _reverseGeocodeWithRetry(
    places,
    position.latitude,
    position.longitude,
  );
  return place ?? _coordinateFallback(position.latitude, position.longitude);
});

Future<ReverseGeocodePlace?> _reverseGeocodeWithRetry(
  GooglePlacesService places,
  double latitude,
  double longitude,
) async {
  for (var attempt = 0;
      attempt <= _reverseGeocodeRetryDelays.length;
      attempt += 1) {
    try {
      final place = await places.reverseGeocodePlace(latitude, longitude);
      if (place != null && place.address.trim().isNotEmpty) return place;
    } catch (error) {
      debugPrint(
        '[LOC] current-location reverse-geocode attempt '
        '${attempt + 1} failed: $error',
      );
    }

    if (attempt < _reverseGeocodeRetryDelays.length) {
      await Future<void>.delayed(_reverseGeocodeRetryDelays[attempt]);
    }
  }
  return null;
}

ReverseGeocodePlace _coordinateFallback(double latitude, double longitude) {
  return ReverseGeocodePlace(
    name: 'Current location',
    address: '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
  );
}

/// Reverse-geocoded label for the device's current position, used in the
/// home greeting and "Artisans" header. The structured place still retains the
/// exact GPS coordinate fallback for booking, but the user-facing label never
/// presents coordinates or a generic GPS status as an address.
final currentLocationLabelProvider = FutureProvider<String>((ref) async {
  final place = await ref.watch(currentLocationPlaceProvider.future);
  if (place.name.trim().toLowerCase() == 'current location') {
    return 'Current location';
  }
  final address = place.address.trim();
  return address.isEmpty ? place.name.trim() : address;
});
