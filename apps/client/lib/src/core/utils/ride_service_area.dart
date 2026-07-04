import 'dart:math' as math;

/// Rider-facing label for the area where ride booking is currently active.
const rideServiceAreaName = 'Kumasi/Ashanti';

/// Approximate centre of the current ride pilot area.
///
/// The backend remains the source of truth through its PostGIS pilot-region
/// check. The client uses this broad radius only for advisory UI copy, so the
/// banner can explain likely failures before the rider reaches fare estimate.
const _kumasiCenterLat = 6.6884;
const _kumasiCenterLng = -1.6244;
const _advisoryRadiusKm = 110.0;

/// Returns true when a GPS fix is likely within the active ride service area.
///
/// This is intentionally broad and advisory. It should never be used to block
/// booking; `/rides/estimate` and `/rides` perform the authoritative region
/// validation server-side.
bool isLikelyInsideRideServiceArea({
  required double latitude,
  required double longitude,
}) {
  return _distanceKm(
        latitude,
        longitude,
        _kumasiCenterLat,
        _kumasiCenterLng,
      ) <=
      _advisoryRadiusKm;
}

bool isLikelyOutsideRideServiceArea({
  required double latitude,
  required double longitude,
}) {
  return !isLikelyInsideRideServiceArea(
    latitude: latitude,
    longitude: longitude,
  );
}

double _distanceKm(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double degrees) => degrees * math.pi / 180.0;
