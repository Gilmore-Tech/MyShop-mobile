import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Models ────────────────────────────────────────────────────────────────────

enum StopType { pickup, intermediate, destination }

class TripStop {
  final String id;
  final StopType type;
  final String address;

  const TripStop({
    required this.id,
    required this.type,
    required this.address,
  });

  TripStop copyWith({StopType? type, String? address}) => TripStop(
        id: id,
        type: type ?? this.type,
        address: address ?? this.address,
      );

  String get typeLabel => switch (type) {
        StopType.pickup => 'PICKUP',
        StopType.intermediate => 'STOP',
        StopType.destination => 'DESTINATION',
      };
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

// ── Mock initial data ─────────────────────────────────────────────────────────

final _initialStops = [
  const TripStop(
    id: 'pickup',
    type: StopType.pickup,
    address: 'Ahodwo Roundabout, Kumasi',
  ),
  const TripStop(
    id: 'stop_1',
    type: StopType.intermediate,
    address: 'Kumasi City Mall (Main Entrance)',
  ),
  const TripStop(
    id: 'destination',
    type: StopType.destination,
    address: 'Manhyia Palace Museum',
  ),
];

const _mockFare = FareRecalculation(
  originalFarePesewas: 4500,
  newFarePesewas: 6250,
  extraMinutes: 14,
  extraKm: 5.2,
  surgeMultiplier: 1.2,
  surgeActive: true,
);

// ── Providers ─────────────────────────────────────────────────────────────────

final tripStopsProvider =
    StateNotifierProvider<TripStopsNotifier, List<TripStop>>(
  (_) => TripStopsNotifier(_initialStops),
);

class TripStopsNotifier extends StateNotifier<List<TripStop>> {
  TripStopsNotifier(List<TripStop> initial) : super(List.of(initial));

  void addIntermediateStop(String address) {
    final destinationIndex =
        state.indexWhere((s) => s.type == StopType.destination);
    final newStop = TripStop(
      id: 'stop_${DateTime.now().millisecondsSinceEpoch}',
      type: StopType.intermediate,
      address: address,
    );
    final updated = List<TripStop>.of(state)
      ..insert(destinationIndex, newStop);
    state = updated;
  }

  void updateStopAddress(String id, String address) {
    state = [
      for (final stop in state)
        if (stop.id == id) stop.copyWith(address: address) else stop,
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
}

/// Fare recalculation — in production, recomputed from backend on stop change.
final fareRecalculationProvider = Provider<FareRecalculation>((_) => _mockFare);
