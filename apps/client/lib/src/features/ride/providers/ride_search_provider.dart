import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which field the destination-search / pin-picker screen is editing.
enum RideSearchField { pickup, destination }

RideSearchField parseRideSearchField(String? raw) =>
    raw == 'destination' ? RideSearchField.destination : RideSearchField.pickup;

/// A selected location — rendered in the home card and carried into the
/// fare-estimate flow. Real implementation will carry lat/lng from Google
/// Places / reverse geocoding.
class RideLocation {
  final String name;
  final String address;
  final double? lat;
  final double? lng;

  const RideLocation({
    required this.name,
    required this.address,
    this.lat,
    this.lng,
  });
}

class RideSearchState {
  final RideLocation? pickup;
  final RideLocation? destination;

  const RideSearchState({this.pickup, this.destination});

  RideSearchState copyWith({RideLocation? pickup, RideLocation? destination}) =>
      RideSearchState(
        pickup: pickup ?? this.pickup,
        destination: destination ?? this.destination,
      );
}

class RideSearchNotifier extends StateNotifier<RideSearchState> {
  RideSearchNotifier()
      : super(
          const RideSearchState(
            pickup: RideLocation(
              name: 'Kumasi Central Market',
              address: 'Adum, Kumasi',
            ),
          ),
        );

  void setLocation(RideSearchField field, RideLocation location) {
    state = field == RideSearchField.pickup
        ? state.copyWith(pickup: location)
        : state.copyWith(destination: location);
  }

  void clear(RideSearchField field) {
    state = field == RideSearchField.pickup
        ? RideSearchState(destination: state.destination)
        : RideSearchState(pickup: state.pickup);
  }
}

final rideSearchProvider =
    StateNotifierProvider<RideSearchNotifier, RideSearchState>(
  (_) => RideSearchNotifier(),
);
