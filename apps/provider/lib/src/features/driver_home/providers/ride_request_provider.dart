import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/provider_status_provider.dart';

// The incoming ride/job request providers are in
// core/providers/socket_provider.dart — driven by Socket.IO events.

/// Active-ride snapshot plus the in-flight flag used to disable buttons
/// while the backend round-trip is pending.
class ActiveRideState {
  const ActiveRideState({
    this.ride,
    this.isUpdating = false,
    this.errorMessage,
  });

  final Ride? ride;
  final bool isUpdating;
  final String? errorMessage;

  bool get hasRide => ride != null;

  ActiveRideState copyWith({
    Ride? ride,
    bool clearRide = false,
    bool? isUpdating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ActiveRideState(
      ride: clearRide ? null : (ride ?? this.ride),
      isUpdating: isUpdating ?? this.isUpdating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Drives the driver-side ride lifecycle.
///
/// Each transition PATCHes /rides/:id/status, waits for the backend, then
/// reflects the new status locally. While the request is in flight,
/// `isUpdating` is true so the UI can disable the primary action.
///
///   requested        → accepted          (driver accepts)
///   accepted         → driver_en_route   (heading to pickup)
///   driver_en_route  → arrived           (at pickup)
///   arrived          → in_progress       (trip started)
///   in_progress      → completed         (trip finished)
class ActiveRideNotifier extends StateNotifier<ActiveRideState> {
  ActiveRideNotifier(this._ref) : super(const ActiveRideState());

  final Ref _ref;

  /// Accept an incoming ride: PATCH the backend, then seed the active-ride
  /// slot and flip the provider to `busy` so the toggle is locked.
  Future<bool> acceptRide(Ride ride) async {
    if (state.isUpdating) return false;
    state = ActiveRideState(ride: ride, isUpdating: true);
    try {
      final json = await _ref.read(rideServiceProvider).updateRideStatus(
            ride.id,
            status: RideStatus.accepted.toJson(),
          );
      final updated = _safeParseRide(json) ??
          ride.copyWith(status: RideStatus.accepted);
      state = ActiveRideState(ride: updated);
      _setBusy();
      return true;
    } on ApiException catch (e) {
      developer.log(
        'acceptRide failed: ${e.errorCode} — ${e.message}',
        name: 'ActiveRide',
        level: 900,
      );
      state = ActiveRideState(errorMessage: _friendlyError(e));
      return false;
    } catch (e) {
      developer.log('acceptRide crashed: $e', name: 'ActiveRide', level: 1000);
      state = const ActiveRideState(
        errorMessage: "Couldn't accept the ride. Please try again.",
      );
      return false;
    }
  }

  /// Advance through the next valid state. Returns true on success — caller
  /// can then read `errorMessage` from state on failure.
  Future<bool> advance() async {
    final ride = state.ride;
    if (ride == null) return false;
    final next = _nextStatusFor(ride.status);
    if (next == null) return false;
    return _transitionTo(next);
  }

  Future<bool> markEnRoute() => _transitionTo(RideStatus.driverEnRoute);
  Future<bool> markArrived() => _transitionTo(RideStatus.arrived);
  Future<bool> startTrip() => _transitionTo(RideStatus.inProgress);
  Future<bool> completeTrip() => _transitionTo(RideStatus.completed);

  Future<bool> _transitionTo(RideStatus next) async {
    final ride = state.ride;
    if (ride == null) return false;
    if (state.isUpdating) return false;
    state = state.copyWith(isUpdating: true, clearError: true);
    try {
      final json = await _ref.read(rideServiceProvider).updateRideStatus(
            ride.id,
            status: next.toJson(),
          );
      final updated = _safeParseRide(json) ?? ride.copyWith(status: next);
      state = state.copyWith(ride: updated, isUpdating: false);
      if (next == RideStatus.completed) {
        _resumeOnline();
      }
      return true;
    } on ApiException catch (e) {
      developer.log(
        'updateRideStatus failed: ${e.errorCode} — ${e.message}',
        name: 'ActiveRide',
        level: 900,
      );
      state = state.copyWith(
        isUpdating: false,
        errorMessage: _friendlyError(e),
      );
      return false;
    } catch (e) {
      developer.log(
        'updateRideStatus crashed: $e',
        name: 'ActiveRide',
        level: 1000,
      );
      state = state.copyWith(
        isUpdating: false,
        errorMessage: 'Could not update the ride. Please try again.',
      );
      return false;
    }
  }

  /// Mirror a `ride:status` socket event into local state — used when the
  /// client cancels mid-trip or the backend pushes a status the driver
  /// didn't trigger.
  void applyRemoteStatus(RideStatus next) {
    final ride = state.ride;
    if (ride == null) return;
    if (ride.status == next) return;
    state = state.copyWith(ride: ride.copyWith(status: next));
    if (next == RideStatus.completed || next == RideStatus.cancelled) {
      _resumeOnline();
    }
  }

  /// Clear the slot and return the driver to `online` — called when the
  /// ride completes, is cancelled, or the user backs out of the flow.
  void clearRide() {
    state = const ActiveRideState();
    _resumeOnline();
  }

  void _setBusy() {
    try {
      _ref.read(providerStatusProvider.notifier).setBusy();
    } catch (_) {
      // Status provider may not be mounted in tests.
    }
  }

  void _resumeOnline() {
    try {
      _ref.read(providerStatusProvider.notifier).resumeAfterJob();
    } catch (_) {}
  }

  Ride? _safeParseRide(Map<String, dynamic> json) {
    try {
      return Ride.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'INVALID_STATUS_TRANSITION':
        return "This ride can't move to the next step right now.";
      case 'NOT_ASSIGNED_DRIVER':
        return 'Only the assigned driver can update this ride.';
      case 'RIDE_ALREADY_ASSIGNED':
        return 'Another driver already accepted this ride.';
      default:
        return e.message;
    }
  }
}

RideStatus? _nextStatusFor(RideStatus current) {
  switch (current) {
    case RideStatus.requested:
      return RideStatus.accepted;
    case RideStatus.accepted:
      return RideStatus.driverEnRoute;
    case RideStatus.driverEnRoute:
      return RideStatus.arrived;
    case RideStatus.arrived:
      return RideStatus.inProgress;
    case RideStatus.inProgress:
      return RideStatus.completed;
    case RideStatus.completed:
    case RideStatus.cancelled:
      return null;
  }
}

final activeRideProvider =
    StateNotifierProvider<ActiveRideNotifier, ActiveRideState>(
  (ref) => ActiveRideNotifier(ref),
);
