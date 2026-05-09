import 'dart:math' as math;

/// Great-circle (Haversine) distance in metres between two lat/lng pairs.
///
/// Pure Dart — no Flutter or geolocator dependency, so it can be used from
/// any layer (widgets, providers, tests, isolates).
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final p1 = lat1 * math.pi / 180.0;
  final p2 = lat2 * math.pi / 180.0;
  final s1 = math.sin(dLat / 2);
  final s2 = math.sin(dLng / 2);
  final h = s1 * s1 + s2 * s2 * math.cos(p1) * math.cos(p2);
  return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}

/// Rough ETA in whole minutes from a straight-line distance and an
/// assumed average ground speed (default 30 km/h ≈ 8.33 m/s — matches
/// the fallback used in the active ride/job screens).
///
/// Returns 0 for non-positive inputs and floors the minimum at 1 min when
/// the provider is already moving toward the client (so the badge never
/// reads "0 min away" while there's still real distance to cover).
int estimatedEtaMinutes(double meters, {double avgKmh = 30}) {
  if (meters <= 0 || avgKmh <= 0) return 0;
  final hours = (meters / 1000) / avgKmh;
  final mins = (hours * 60).round();
  return mins < 1 ? 1 : mins;
}

/// Compact label: "5 min", "45 min", "1h 10m".
String formatEtaLabel(int minutes) {
  if (minutes <= 0) return '—';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
