import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which field the destination-search / pin-picker screen is editing.
enum RideSearchField { pickup, destination }

enum RideLocationPrecision { point, area }

RideSearchField parseRideSearchField(String? raw) =>
    raw == 'destination' ? RideSearchField.destination : RideSearchField.pickup;

/// A selected location — rendered in the home card and carried into the
/// fare-estimate flow.
///
/// A label or saved address without coordinates is intentionally not a precise
/// location. Fare calculation and booking must only use a point confirmed by
/// Places, GPS, or the map pin picker.
class RideLocation {
  final String name;
  final String address;
  final double? lat;
  final double? lng;
  final RideLocationPrecision precision;

  const RideLocation({
    required this.name,
    required this.address,
    this.lat,
    this.lng,
    this.precision = RideLocationPrecision.point,
  });

  bool get hasCoordinates {
    final latitude = lat;
    final longitude = lng;
    return latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  bool get isPrecise =>
      precision == RideLocationPrecision.point && hasCoordinates;
}

class RideSearchState {
  final RideLocation? pickup;
  final RideLocation? destination;
  final bool wasSubmitted;

  const RideSearchState({
    this.pickup,
    this.destination,
    this.wasSubmitted = false,
  });

  RideSearchState copyWith({
    RideLocation? pickup,
    RideLocation? destination,
    bool? wasSubmitted,
  }) =>
      RideSearchState(
        pickup: pickup ?? this.pickup,
        destination: destination ?? this.destination,
        wasSubmitted: wasSubmitted ?? this.wasSubmitted,
      );
}

class RideSearchNotifier extends StateNotifier<RideSearchState> {
  RideSearchNotifier() : super(const RideSearchState());

  void setLocation(RideSearchField field, RideLocation location) {
    state = field == RideSearchField.pickup
        ? state.copyWith(pickup: location, wasSubmitted: false)
        : state.copyWith(destination: location, wasSubmitted: false);
  }

  /// Marks these endpoints as consumed by an authoritative ride creation.
  /// If completion delivery is missed while the app is backgrounded, Home can
  /// still distinguish the previous ride's pickup from a new manual choice.
  void markSubmitted() {
    state = state.copyWith(wasSubmitted: true);
  }

  void clear(RideSearchField field) {
    state = field == RideSearchField.pickup
        ? RideSearchState(destination: state.destination)
        : RideSearchState(pickup: state.pickup);
  }

  /// Wipe both endpoints. Called when the user backs out of / cancels
  /// the Plan Your Trip screen — without this, the next entry into the
  /// fare-estimate flow shows the previous pickup + destination, which
  /// the user reads as "the app remembered a trip I already cancelled".
  /// Pickup is also cleared so the home screen's auto-seed from current
  /// location fires fresh on the next visit.
  void reset() {
    state = const RideSearchState();
  }
}

final rideSearchProvider =
    StateNotifierProvider<RideSearchNotifier, RideSearchState>(
  (_) => RideSearchNotifier(),
);
