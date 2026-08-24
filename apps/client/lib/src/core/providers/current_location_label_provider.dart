import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../services/google_places_service.dart';
import 'current_location_provider.dart';

typedef LocationCoordinates = ({double latitude, double longitude});

/// One coordinate-bound reverse-geocode operation shared by every consumer.
///
/// Home's current-location label and the automatic ride pickup can request the
/// same point on the same frame. A family provider gives that point one
/// in-flight request/result instead of sending duplicate backend/Google calls.
/// Unobserved results stay alive briefly so sequential consumers in the same
/// booking flow also share the lookup. The currently displayed coordinate may
/// remain cached while Home observes it; old coordinates auto-dispose.
final reverseGeocodedPlaceProvider = FutureProvider.autoDispose
    .family<ReverseGeocodePlace, LocationCoordinates>((ref, coordinates) async {
  final keepAlive = ref.keepAlive();
  final expiry = Timer(const Duration(seconds: 30), keepAlive.close);
  ref.onDispose(expiry.cancel);

  final places = ref.watch(reverseGeocodingServiceProvider);
  ReverseGeocodePlace? place;
  try {
    place = await places.reverseGeocodePlace(
      coordinates.latitude,
      coordinates.longitude,
    );
  } catch (error) {
    debugPrint('[LOC] current-location reverse-geocode failed: $error');
  }
  if (place != null && place.address.trim().isNotEmpty) return place;
  return _coordinateFallback(
    coordinates.latitude,
    coordinates.longitude,
  );
});

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

  return ref.watch(
    reverseGeocodedPlaceProvider((
      latitude: position.latitude,
      longitude: position.longitude,
    )).future,
  );
});

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
