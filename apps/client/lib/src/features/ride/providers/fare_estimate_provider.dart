import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'ride_provider.dart';
import 'ride_search_provider.dart';

// ── Vehicle category templates ────────────────────────────────────────────────
//
// The backend returns one fare for the route. Each category applies a
// multiplier to derive its own price. Prices are always rounded UP to the
// nearest whole GHS (matching backend behaviour — PRD edge case #11).

class _CategoryTemplate {
  final String id;
  final String name;
  final String description;
  final int capacityPersons;
  final double fareMultiplier;
  final int etaOffsetMins; // added to/subtracted from pickupEtaMins
  final bool isMotorcycle;

  const _CategoryTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.capacityPersons,
    required this.fareMultiplier,
    required this.etaOffsetMins,
    required this.isMotorcycle,
  });
}

const _kCategories = [
  _CategoryTemplate(
    id: 'ride_comfort',
    name: 'Ride Comfort',
    description: 'Newer cars with extra legroom',
    capacityPersons: 4,
    fareMultiplier: 1.0,
    etaOffsetMins: 0,
    isMotorcycle: false,
  ),
  _CategoryTemplate(
    id: 'moto_ride',
    name: 'Moto-Ride',
    description: 'Beat the heavy traffic',
    capacityPersons: 1,
    fareMultiplier: 0.55,
    etaOffsetMins: -2,
    isMotorcycle: true,
  ),
];

int _roundUpToGhs(int pesewas) {
  final rem = pesewas % 100;
  return rem == 0 ? pesewas : pesewas + (100 - rem);
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Calls POST /rides/estimate and returns a priced [VehicleOption] per
/// vehicle category. Automatically re-fetches when pickup or destination
/// coordinates change. Returns an empty list (no error) until both
/// coordinates are available.
final fareEstimateProvider = FutureProvider<List<VehicleOption>>((ref) async {
  final search = ref.watch(rideSearchProvider);
  final pickup = search.pickup;
  final destination = search.destination;

  if (pickup?.lat == null ||
      pickup?.lng == null ||
      destination?.lat == null ||
      destination?.lng == null) {
    return [];
  }

  final rideService = ref.read(rideServiceProvider);
  final result = await rideService.estimate(
    pickupLat: pickup!.lat!,
    pickupLng: pickup.lng!,
    destinationLat: destination!.lat!,
    destinationLng: destination.lng!,
  );

  final baseFarePesewas = (result['estimatedFarePesewas'] as num).toInt();
  final surgeMultiplier =
      (result['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
  final distanceKm = (result['distanceKm'] as num?)?.toDouble() ?? 0.0;
  final durationMins = (result['durationMins'] as num?)?.toInt() ?? 0;
  final pickupEtaMins = (result['pickupEtaMins'] as num?)?.toInt() ?? 5;

  developer.log(
    'Estimate: ₵${(baseFarePesewas / 100).toStringAsFixed(2)} '
    '· ${distanceKm}km · ${durationMins}min · surge ${surgeMultiplier}x',
    name: 'FareEstimate',
  );

  return _kCategories.map((cat) {
    final fare = _roundUpToGhs((baseFarePesewas * cat.fareMultiplier).ceil());
    final eta = (pickupEtaMins + cat.etaOffsetMins).clamp(1, 99);
    return VehicleOption(
      id: cat.id,
      name: cat.name,
      description: cat.description,
      capacityPersons: cat.capacityPersons,
      farePesewas: fare,
      estimatedTime: '$eta min',
      isMotorcycle: cat.isMotorcycle,
      distanceKm: distanceKm,
      durationMins: durationMins,
      // 1.05× threshold — backend's baseline can drift to 1.0001 due to
      // float rounding inside the surge engine, which used to flicker
      // the "Surge Pricing Active" banner during off-peak hours.
      // Anything below a 5% multiplier isn't a meaningful surge anyway.
      surgeActive: surgeMultiplier > 1.05,
      surgeMultiplier: surgeMultiplier,
    );
  }).toList();
});
