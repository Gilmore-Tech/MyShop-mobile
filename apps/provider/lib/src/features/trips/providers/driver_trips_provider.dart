import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';

/// Driver-side trip history. Backed by `GET /v1/rides` — the same endpoint
/// the rider uses, but the backend filters server-side based on the bearer
/// token's userId, so the response is the driver's own ride list.
///
/// Refreshes:
///   - First mount of any consumer (FutureProvider builds once).
///   - On `ride:state` `completed` snapshot — the driver socket listener
///     invalidates this provider so the row appears the moment the trip
///     ends, no pull-to-refresh needed (mirrors the earnings providers).
///   - Manual `ref.invalidate(driverTripsProvider)` (date-range filters,
///     pull-to-refresh).
final driverTripsProvider = FutureProvider<List<Ride>>((ref) async {
  try {
    final raw = await ref.watch(rideServiceProvider).listRides(limit: 50);
    return raw
        .whereType<Map<String, dynamic>>()
        .map((j) {
          try {
            return Ride.fromJson(j);
          } catch (_) {
            return null;
          }
        })
        .whereType<Ride>()
        .toList(growable: false);
  } catch (_) {
    return const <Ride>[];
  }
});
