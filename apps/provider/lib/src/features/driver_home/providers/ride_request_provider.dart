import 'dart:async';
import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../../core/providers/socket_provider.dart';
import 'active_ride_persistence.dart';

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
/// Acceptance is a WebSocket call (`ride:accept`) because the backend's
/// REST `PATCH /rides/:id/status` endpoint only handles transitions out of
/// `accepted` and won't accept a `requested → accepted` move. The socket
/// path also wins the race against other notified drivers (Redis-backed
/// first-come) and broadcasts `ride:accepted` to the rider's tracking room.
///
/// Subsequent transitions go through REST PATCH:
///   accepted         → driver_en_route   (heading to pickup)
///   driver_en_route  → arrived_at_pickup (at pickup)
///   arrived          → in_progress       (trip started)
///   in_progress      → completed         (trip finished)
class ActiveRideNotifier extends StateNotifier<ActiveRideState> {
  ActiveRideNotifier(this._ref) : super(const ActiveRideState());

  final Ref _ref;

  /// Accept an incoming ride. Sends the `ride:accept` socket event and
  /// awaits the backend's ack — the backend atomically assigns the ride
  /// (first driver wins) and broadcasts `ride:accepted` to the rider on
  /// our behalf.
  Future<bool> acceptRide(Ride ride) async {
    if (state.isUpdating) return false;
    state = ActiveRideState(ride: ride, isUpdating: true);
    try {
      final socket = _ref.read(socketServiceProvider);
      final ack = await socket.emitWithAck(
        'ride:accept',
        {'rideId': ride.id},
      );
      developer.log('ride:accept ack: $ack', name: 'ActiveRide');

      // Backend ack returns either `driverPayload` (success) or an
      // exception event. On success the response is a Map containing at
      // least `rideId` and `status: 'accepted'`. Anything else is treated
      // as a failure so the user sees a clear error instead of a stuck
      // active-ride screen.
      final ackMap = ack is Map ? Map<String, dynamic>.from(ack) : null;
      final ackError = ackMap?['error'] as String?;
      if (ackError != null) {
        state = ActiveRideState(errorMessage: _friendlyAckError(ackError));
        return false;
      }

      state = ActiveRideState(
        ride: ride.copyWith(status: RideStatus.accepted),
      );
      _setBusy();
      // Persist the id so a crash or force-quit doesn't leave the driver
      // permanently flagged `busy` on the backend with no way for the app
      // to know there's a stuck ride to resume / cancel.
      unawaited(ActiveRidePersistence().save(ride.id));
      // The slim `ride:new` broadcast omits client name/photo/rating to
      // keep the request modal lean. Now that we've accepted, fetch the
      // full ride so the active-ride screen shows real passenger info
      // instead of "Passenger" and a default rating.
      unawaited(_hydrateRide(ride.id));
      // Eagerly advance `accepted → driver_en_route`. The backend's
      // RideStageTimeoutService auto-cancels rides that sit in `accepted`
      // for ~2 minutes, and the PATCH is the only way for the driver to
      // promise they're heading to the pickup. Doing this here (rather
      // than from the screen's initState) means it fires the moment the
      // socket ack lands, immune to widget-lifecycle / Riverpod build
      // guards that were silently swallowing the call before.
      unawaited(markEnRoute());
      return true;
    } on TimeoutException {
      developer.log('acceptRide timed out', name: 'ActiveRide', level: 900);
      state = const ActiveRideState(
        errorMessage:
            "We didn't hear back from the server. Please try again.",
      );
      return false;
    } on StateError catch (e) {
      developer.log('acceptRide socket error: $e',
          name: 'ActiveRide', level: 900);
      state = const ActiveRideState(
        errorMessage: "Connection lost — please try again.",
      );
      return false;
    } catch (e) {
      developer.log('acceptRide crashed: $e', name: 'ActiveRide', level: 1000);
      state = const ActiveRideState(
        errorMessage: "Couldn't accept the ride. Please try again.",
      );
      return false;
    }
  }

  String _friendlyAckError(String code) {
    switch (code) {
      case 'ACCEPTANCE_TIMEOUT':
        return 'This ride request expired before you could accept it.';
      case 'RIDE_ALREADY_ACCEPTED':
        return 'Another driver already accepted this ride.';
      case 'RIDE_NOT_ASSIGNED':
        return 'This ride request was not sent to you.';
      case 'DRIVER_PROFILE_REQUIRED':
        return 'Your driver profile is incomplete — finish verification to accept rides.';
      default:
        return 'Could not accept the ride. Please try again.';
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
        unawaited(ActiveRidePersistence().clear());
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

  /// Cancel the active ride. Best-effort PATCH so the backend gets a
  /// proper `cancelled` row, then ALWAYS clear local state + persistence
  /// — even if the backend refuses (data corruption, Prisma error,
  /// network drop) the driver should still be able to escape the screen
  /// rather than be permanently stuck on a ride they can't progress.
  Future<void> cancelRide({String? reason}) async {
    final ride = state.ride;
    if (ride == null) {
      clearRide();
      return;
    }
    state = state.copyWith(isUpdating: true, clearError: true);
    try {
      await _ref.read(rideServiceProvider).cancelRide(
            ride.id,
            reason: reason ?? 'driver_cancelled',
          );
      developer.log('cancelRide PATCH succeeded for ${ride.id}',
          name: 'ActiveRide');
    } on ApiException catch (e) {
      developer.log(
        'cancelRide PATCH failed: ${e.errorCode} — ${e.message} '
        '(clearing local state anyway)',
        name: 'ActiveRide',
        level: 900,
      );
    } catch (e) {
      developer.log(
        'cancelRide crashed: $e (clearing local state anyway)',
        name: 'ActiveRide',
        level: 1000,
      );
    }
    clearRide();
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
      unawaited(ActiveRidePersistence().clear());
    }
  }

  /// Restore an active ride from the recovery flow on app start. Skips the
  /// persistence write (the id is already on disk) and the busy-toggle
  /// (the bridge will reconcile it from the ride status).
  void restore(Ride ride) {
    state = ActiveRideState(ride: ride);
    _setBusy();
  }

  /// Clear the slot and return the driver to `online` — called when the
  /// ride completes, is cancelled, or the user backs out of the flow.
  void clearRide() {
    state = const ActiveRideState();
    _resumeOnline();
    unawaited(ActiveRidePersistence().clear());
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

  /// Pull the full ride entity from REST and replace local state with it.
  /// Called after a successful socket accept so the screen can render real
  /// client name / photo / rating instead of the slim broadcast's defaults.
  /// Failures are non-fatal — the screen falls back to whatever fields the
  /// `ride:new` broadcast did include.
  Future<void> _hydrateRide(String rideId) async {
    try {
      final json = await _ref.read(rideServiceProvider).getRide(rideId);
      final fresh = Ride.fromJson(json);
      final current = state.ride;
      if (current == null || current.id != rideId) return;
      // Preserve the local lifecycle status — by the time hydrate returns,
      // the auto-driverEnRoute kick (or a later transition the user just
      // triggered) may have already advanced past what the backend's GET
      // returned, and we don't want to silently regress.
      state = state.copyWith(ride: fresh.copyWith(status: current.status));
    } catch (e) {
      developer.log('hydrateRide failed: $e', name: 'ActiveRide', level: 800);
    }
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
