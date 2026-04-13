import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Incoming ride request — real requests will come via WebSocket (future).
final incomingRideRequestProvider = StateProvider<Ride?>((ref) {
  return null;
});

/// Provider for the active ride in progress.
class ActiveRideNotifier extends StateNotifier<Ride?> {
  ActiveRideNotifier() : super(null);

  void acceptRide(Ride ride) {
    state = ride.copyWith(status: RideStatus.accepted);
  }

  void markEnRoute() {
    if (state != null) {
      state = state!.copyWith(status: RideStatus.driverEnRoute);
    }
  }

  void markArrived() {
    if (state != null) {
      state = state!.copyWith(status: RideStatus.arrived);
    }
  }

  void startTrip() {
    if (state != null) {
      state = state!.copyWith(status: RideStatus.inProgress);
    }
  }

  void completeTrip() {
    if (state != null) {
      state = state!.copyWith(status: RideStatus.completed);
    }
  }

  void cancelTrip() {
    state = null;
  }

  void clearRide() {
    state = null;
  }
}

final activeRideProvider =
    StateNotifierProvider<ActiveRideNotifier, Ride?>((ref) {
  return ActiveRideNotifier();
});
