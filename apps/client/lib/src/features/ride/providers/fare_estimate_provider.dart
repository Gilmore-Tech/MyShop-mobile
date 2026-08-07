import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'edit_trip_provider.dart';
import 'ride_provider.dart';
import 'ride_search_provider.dart';

// ── Provider ──────────────────────────────────────────────────────────────────
//
// The backend now prices each ride category server-side and returns one priced
// entry per active category (Regular, Comfort, …) with its own fare and
// per-category driver-availability flag. The client renders one selectable card
// per entry — the `id` IS the category slug, which the booking flow sends back
// on POST /rides so pricing and matching stay category-exclusive.

const _pretripMultistopFlagKey = 'ride_multistop_pretrip_enabled';

/// Runtime flag for booking-time multi-stop rides. Defaults closed if the
/// backend key is missing/unreachable, so production keeps the single-trip flow
/// stable while staging tests the feature.
final pretripMultistopEnabledProvider = FutureProvider<bool>((ref) async {
  final config = ref.read(platformConfigServiceProvider);
  try {
    return await config.getBoolean(_pretripMultistopFlagKey) ?? false;
  } catch (_) {
    return false;
  }
});

/// Calls POST /rides/estimate and returns a priced [VehicleOption] per active
/// ride category. Automatically re-fetches when pickup or destination
/// coordinates change. Returns an empty list (no error) until both
/// coordinates are available.
final fareEstimateProvider = FutureProvider<List<VehicleOption>>((ref) async {
  final search = ref.watch(rideSearchProvider);
  final tripStops = ref.watch(tripStopsProvider);
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

  final candidateStops = tripStops
      .where(
        (s) =>
            s.type == StopType.intermediate && s.lat != null && s.lng != null,
      )
      .toList();
  final multistopEnabled = candidateStops.isNotEmpty
      ? await ref.watch(pretripMultistopEnabledProvider.future)
      : false;
  final pricedStops = multistopEnabled
      ? candidateStops.map((s) => {'lat': s.lat!, 'lng': s.lng!}).toList()
      : const <Map<String, double>>[];

  final rideService = ref.read(rideServiceProvider);
  final result = await rideService.estimate(
    pickupLat: pickup.lat!,
    pickupLng: pickup.lng!,
    destinationLat: destination.lat!,
    destinationLng: destination.lng!,
    stops: pricedStops.isEmpty ? null : pricedStops,
  );

  final surgeMultiplier =
      (result['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
  final distanceKm = _distanceKmFromEstimate(result);
  final durationMins = _durationMinsFromEstimate(result);
  final categories = (result['categories'] as List?) ?? const [];

  developer.log(
    'Estimate: ${categories.length} categories · ${distanceKm}km '
    '· ${durationMins}min · ${pricedStops.length} stops · surge ${surgeMultiplier}x',
    name: 'FareEstimate',
  );

  return categories.map((raw) {
    final cat = raw as Map<String, dynamic>;
    final slug = cat['slug'] as String;
    final eta = (cat['pickupEtaMins'] as num?)?.toInt() ?? 5;
    // Optional promo object — when present, `estimatedFarePesewas` is
    // ALREADY discounted; `originalFarePesewas` is the pre-promo fare
    // shown struck through. Absent key (old backend) = no promo.
    final promo = cat['promo'];
    final promoMap = promo is Map<String, dynamic> ? promo : null;
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
      promoName: promoMap?['name'] as String?,
      promoOriginalFarePesewas:
          (promoMap?['originalFarePesewas'] as num?)?.toInt(),
    );
  }).toList();
});

double _distanceKmFromEstimate(Map<String, dynamic> result) {
  final km = _readNum(
    result,
    const ['distanceKm', 'estimatedDistanceKm', 'actualDistanceKm'],
  );
  if (km != null) return km.toDouble();

  final meters = _readNum(
    result,
    const ['distanceMeters', 'estimatedDistanceMeters', 'actualDistanceMeters'],
  );
  if (meters != null) return meters / 1000;

  return 0.0;
}

int _durationMinsFromEstimate(Map<String, dynamic> result) {
  final minutes = _readNum(
    result,
    const ['durationMins', 'estimatedDurationMins', 'actualDurationMins'],
  );
  if (minutes != null) return minutes.toInt();

  final seconds = _readNum(
    result,
    const [
      'durationSeconds',
      'estimatedDurationSeconds',
      'actualDurationSeconds',
    ],
  );
  if (seconds != null) return (seconds / 60).round();

  return 0;
}

double? _readNum(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = num.tryParse(value);
      if (parsed != null) return parsed.toDouble();
    }
  }
  return null;
}
