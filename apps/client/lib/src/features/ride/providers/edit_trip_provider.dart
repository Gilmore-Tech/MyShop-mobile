import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' as models;

import '../../../core/di/providers.dart';
import 'ride_provider.dart' show activeRideIdProvider, matchedDriverProvider;
import 'ride_search_provider.dart';

// ── Models ────────────────────────────────────────────────────────────────────

enum StopType { pickup, intermediate, destination }

/// One row in the route review screen. The same model covers pickup,
/// destination, and any intermediate stops the rider has already added or
/// is about to add. [backendStopId] is null for stops that haven't been
/// synced to the backend yet — those are the rows the confirm action
/// pushes through `PATCH /v1/rides/:id/stops`.
class TripStop {
  final String id;
  final StopType type;
  final String address;
  final double? lat;
  final double? lng;

  /// Server-issued id once the stop has been persisted via
  /// `PATCH /rides/:id/stops`. Null until the round-trip lands.
  final String? backendStopId;

  const TripStop({
    required this.id,
    required this.type,
    required this.address,
    this.lat,
    this.lng,
    this.backendStopId,
  });

  TripStop copyWith({
    StopType? type,
    String? address,
    double? lat,
    double? lng,
    String? backendStopId,
  }) =>
      TripStop(
        id: id,
        type: type ?? this.type,
        address: address ?? this.address,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        backendStopId: backendStopId ?? this.backendStopId,
      );

  String get typeLabel => switch (type) {
        StopType.pickup => 'PICKUP',
        StopType.intermediate => 'STOP',
        StopType.destination => 'DESTINATION',
      };

  /// True when this row is a fresh intermediate stop the rider is in the
  /// middle of adding — not yet on the server, no backend id.
  bool get isPendingNewStop =>
      type == StopType.intermediate && backendStopId == null;
}

class FareRecalculation {
  final int originalFarePesewas;
  final int newFarePesewas;
  final int extraMinutes;
  final double extraKm;
  final double surgeMultiplier;
  final bool surgeActive;

  const FareRecalculation({
    required this.originalFarePesewas,
    required this.newFarePesewas,
    required this.extraMinutes,
    required this.extraKm,
    required this.surgeMultiplier,
    required this.surgeActive,
  });

  int get differencePesewas => newFarePesewas - originalFarePesewas;
  bool get isSurgeIncrease => differencePesewas > 0;

  String _fmt(int pesewas) =>
      'GH₵ ${(pesewas / 100).toStringAsFixed(2)}';

  String get originalFareDisplay => _fmt(originalFarePesewas);
  String get newFareDisplay => _fmt(newFarePesewas);

  String get differenceDisplay {
    final prefix = isSurgeIncrease ? '+' : '-';
    return '$prefix${_fmt(differencePesewas.abs())}';
  }

  String get surgeLabel =>
      'Surge Active ${surgeMultiplier.toStringAsFixed(1)}x';
}

// ── Providers ─────────────────────────────────────────────────────────────────

final tripStopsProvider =
    StateNotifierProvider<TripStopsNotifier, List<TripStop>>(
  TripStopsNotifier.new,
);

class TripStopsNotifier extends StateNotifier<List<TripStop>> {
  TripStopsNotifier(this._ref) : super(const []);

  final Ref _ref;

  /// Replace the local row list with pickup + already-persisted stops +
  /// destination, sourced from whatever provider holds the live ride
  /// state (search state for pre-trip, [models.Ride] from REST/snapshot
  /// for in-trip). Idempotent — calling repeatedly is fine.
  void seed({
    required ({String? address, double? lat, double? lng}) pickup,
    required ({String? address, double? lat, double? lng}) destination,
    List<models.RideStop> existingStops = const [],
  }) {
    final pickupRow = TripStop(
      id: 'pickup',
      type: StopType.pickup,
      address: pickup.address ?? '',
      lat: pickup.lat,
      lng: pickup.lng,
      backendStopId: 'pickup',
    );
    final destinationRow = TripStop(
      id: 'destination',
      type: StopType.destination,
      address: destination.address ?? '',
      lat: destination.lat,
      lng: destination.lng,
      backendStopId: 'destination',
    );
    final intermediates = [
      for (var i = 0; i < existingStops.length; i++)
        TripStop(
          // Backend-assigned ids aren't on RideStop yet; key by index +
          // address so reorders stay stable across rebuilds.
          id: 'remote_$i',
          type: StopType.intermediate,
          address: existingStops[i].address,
          lat: existingStops[i].lat,
          lng: existingStops[i].lng,
          // Treating remote stops as already-synced — even without an
          // explicit id, we don't want to re-PATCH them on confirm.
          backendStopId: 'remote_$i',
        ),
    ];
    state = [pickupRow, ...intermediates, destinationRow];
  }

  void addIntermediateStop(
    String address, {
    double? lat,
    double? lng,
  }) {
    final destinationIndex =
        state.indexWhere((s) => s.type == StopType.destination);
    final newStop = TripStop(
      id: 'stop_${DateTime.now().millisecondsSinceEpoch}',
      type: StopType.intermediate,
      address: address,
      lat: lat,
      lng: lng,
    );
    final updated = List<TripStop>.of(state);
    if (destinationIndex >= 0) {
      updated.insert(destinationIndex, newStop);
    } else {
      updated.add(newStop);
    }
    state = updated;
  }

  void updateStopAddress(
    String id,
    String address, {
    double? lat,
    double? lng,
  }) {
    state = [
      for (final stop in state)
        if (stop.id == id)
          stop.copyWith(address: address, lat: lat, lng: lng)
        else
          stop,
    ];
  }

  void removeStop(String id) {
    state = state.where((s) => s.id != id).toList();
  }

  void reorder(int oldIndex, int newIndex) {
    // Prevent moving pickup or destination outside their bounds
    final stops = List<TripStop>.of(state);
    if (oldIndex == 0 || newIndex == 0) return; // never move pickup
    if (oldIndex == stops.length - 1 ||
        newIndex >= stops.length) {
      return; // never move destination
    }

    if (newIndex > oldIndex) newIndex -= 1;
    final item = stops.removeAt(oldIndex);
    stops.insert(newIndex, item);
    state = stops;
  }

  /// Push every locally-added intermediate stop to the backend via
  /// `PATCH /v1/rides/:id/stops`. Returns the number of stops actually
  /// submitted; throws on the first hard error so the screen can show
  /// the message and let the rider retry.
  ///
  /// Stops without coords are skipped — they came from a free-text edit
  /// the search screen couldn't geocode, and the backend rejects them.
  Future<int> submitNewStopsToBackend() async {
    final rideId = _ref.read(activeRideIdProvider);
    if (rideId == null || rideId.isEmpty) {
      throw StateError("No active ride to attach stops to.");
    }
    final rideService = _ref.read(rideServiceProvider);
    final pending = state
        .where((s) => s.isPendingNewStop && s.lat != null && s.lng != null)
        .toList();
    var submitted = 0;
    for (final stop in pending) {
      final result = await rideService.addStop(
        rideId,
        lat: stop.lat!,
        lng: stop.lng!,
        address: stop.address.isEmpty ? null : stop.address,
      );
      submitted++;
      developer.log(
        'addStop OK rideId=$rideId stopId=${result['id']}',
        name: 'TripStops',
      );
      // Mark local row as synced so a retry doesn't re-submit.
      state = [
        for (final row in state)
          if (row.id == stop.id)
            row.copyWith(backendStopId: result['id'] as String? ?? row.id)
          else
            row,
      ];
    }
    return submitted;
  }
}

/// Fare recalculation surfaced on the review screen. Today the backend's
/// `ride:route_updated` event carries `newFarePesewas`; once the client
/// listens for it the hook here will swap to a [StateProvider] driven by
/// that event. Until then, [matchedDriverProvider] gives us the original
/// confirmed fare and we leave the projected new fare equal to it (so
/// "Difference: 0" reads as honest until the backend recalculates).
final fareRecalculationProvider = Provider<FareRecalculation>((ref) {
  final matched = ref.watch(matchedDriverProvider);
  final original = matched?.confirmedFarePesewas ?? 0;
  return FareRecalculation(
    originalFarePesewas: original,
    newFarePesewas: original,
    extraMinutes: 0,
    extraKm: 0,
    surgeMultiplier: 1.0,
    surgeActive: false,
  );
});

/// Convenience: seeds [tripStopsProvider] from the rider's current trip
/// state. Call once from the Add Stop screen's `initState` so the user
/// starts with their real pickup/destination instead of mocks. Falls
/// back to whatever `rideSearchProvider` has (pre-trip) when there's no
/// active ride yet.
void seedTripStopsFromCurrentRide(WidgetReader read) {
  final search = read(rideSearchProvider);
  read(tripStopsProvider.notifier).seed(
    pickup: (
      address: search.pickup?.address ?? search.pickup?.name,
      lat: search.pickup?.lat,
      lng: search.pickup?.lng,
    ),
    destination: (
      address: search.destination?.address ?? search.destination?.name,
      lat: search.destination?.lat,
      lng: search.destination?.lng,
    ),
  );
}

/// Tiny abstraction so the seed helper works with both `Ref.read` and
/// `WidgetRef.read` tear-offs.
typedef WidgetReader = T Function<T>(ProviderListenable<T>);
