import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'ride_provider.dart';
import 'ride_search_provider.dart';

// ── Provider ──────────────────────────────────────────────────────────────────
//
// The backend now prices each ride category server-side and returns one priced
// entry per active category (Regular, Comfort, …) with its own fare and
// per-category driver-availability flag. The client renders one selectable card
// per entry — the `id` IS the category slug, which the booking flow sends back
// on POST /rides so pricing and matching stay category-exclusive.

/// Calls POST /rides/estimate and returns a priced [VehicleOption] per active
/// ride category. Automatically re-fetches when pickup or destination
/// coordinates change. Returns an empty list (no error) until both
/// coordinates are available.
final fareEstimateProvider = FutureProvider<List<VehicleOption>>((ref) async {
  final search = ref.watch(rideSearchProvider);
  final pickup = search.pickup;
  final destination = search.destination;

  if (pickup == null ||
      destination == null ||
      pickup.lat == null ||
      pickup.lng == null ||
      destination.lat == null ||
      destination.lng == null ||
      !pickup.isPrecise ||
      !destination.isPrecise) {
    return [];
  }

  final rideService = ref.read(rideServiceProvider);
  final result = await rideService.estimate(
    pickupLat: pickup.lat!,
    pickupLng: pickup.lng!,
    destinationLat: destination.lat!,
    destinationLng: destination.lng!,
  );

  final surgeMultiplier =
      (result['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
  final distanceKm = (result['distanceKm'] as num?)?.toDouble() ?? 0.0;
  final durationMins = (result['durationMins'] as num?)?.toInt() ?? 0;
  final categories = (result['categories'] as List?) ?? const [];

  developer.log(
    'Estimate: ${categories.length} categories · ${distanceKm}km '
    '· ${durationMins}min · surge ${surgeMultiplier}x',
    name: 'FareEstimate',
  );

  return categories.map((raw) {
    final cat = raw as Map<String, dynamic>;
    final slug = cat['slug'] as String;
    final eta = (cat['pickupEtaMins'] as num?)?.toInt() ?? 5;
    return VehicleOption(
      // id carries the slug so the booking flow can send it back on POST /rides.
      id: slug,
      name: cat['name'] as String? ?? slug,
      description: cat['description'] as String? ?? '',
      capacityPersons: (cat['capacityPersons'] as num?)?.toInt() ?? 4,
      farePesewas: (cat['estimatedFarePesewas'] as num).toInt(),
      estimatedTime: '$eta min',
      // Motorcycle tiers are identified by slug convention (none seeded today).
      isMotorcycle: slug.contains('moto'),
      distanceKm: distanceKm,
      durationMins: durationMins,
      // 1.05× threshold — backend's baseline can drift to 1.0001 due to
      // float rounding inside the surge engine, which used to flicker
      // the "Surge Pricing Active" banner during off-peak hours.
      surgeActive: surgeMultiplier > 1.05,
      surgeMultiplier: surgeMultiplier,
      // Per-category availability — a Comfort card greys out when only Regular
      // drivers are online.
      driversAvailable: (cat['driversAvailable'] as bool?) ?? true,
    );
  }).toList();
});
