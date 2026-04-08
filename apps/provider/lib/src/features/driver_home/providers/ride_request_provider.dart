import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Mock incoming ride request for UI development.
final incomingRideRequestProvider = StateProvider<Ride?>((ref) {
  return Ride(
    id: 'RID-92834',
    clientId: 'client-001',
    status: RideStatus.requested,
    pickupAddress: 'Oxford Street, Osu (Near Shoprite)',
    dropoffAddress: 'Kotoka Intl Airport (Terminal 3)',
    pickupLat: 5.5560,
    pickupLng: -0.1824,
    dropoffLat: 5.6050,
    dropoffLng: -0.1716,
    estimatedFarePesewas: 4550,
    estimatedDistanceKm: 1.2,
    estimatedDurationMins: 4,
    surgeMultiplier: 1.0,
    paymentMethod: 'Mobile Money',
    createdAt: DateTime.now(),
    clientName: 'Kwame Ansah',
    clientRating: 4.9,
    clientTripCount: 240,
  );
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
