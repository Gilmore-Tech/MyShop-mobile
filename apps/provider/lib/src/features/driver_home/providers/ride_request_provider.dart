import 'dart:async';
import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../../core/providers/socket_provider.dart';
import '../../earnings/providers/earnings_providers.dart';
import '../../earnings/providers/ratings_provider.dart';
import '../../trips/providers/driver_trips_provider.dart';

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

/// Outcome of a driver-side ride cancellation. The backend returns the
/// fee deducted from the driver's earnings and a flag that flips to `true`
/// when this cancellation just tripped the suspension threshold for the
/// rolling 30-day window — the UI should call out both clearly.
class RideCancelOutcome {
  const RideCancelOutcome({
    this.feePesewas = 0,
    this.driverSuspended = false,
    this.driverNoShow = false,
  });

  final int feePesewas;
  final bool driverSuspended;

  /// True when the backend treated this as a client no-show (driver waited out
  /// the free window before cancelling) — no rating/counter penalty applied.
  final bool driverNoShow;

  bool get hasFee => feePesewas > 0;
}

/// Drives the driver-side ride lifecycle.
///
/// Acceptance is a WebSocket call (`ride:accept`) — the backend atomically
/// assigns the ride (first driver wins) and broadcasts `ride:state` to the
/// driver's and rider's rooms.
///
/// Subsequent transitions go through REST `PATCH /rides/:id/status`, which
/// is now idempotent on the backend: passing any forward status walks the
/// state machine in one transaction. After every transition the backend
/// emits a fresh `ride:state` snapshot which the socket listener applies
/// via [applySnapshot]. This notifier therefore stops trying to maintain
/// its own copy of the lifecycle — it just reflects whatever the backend
/// broadcasts.
class ActiveRideNotifier extends StateNotifier<ActiveRideState> {
  ActiveRideNotifier(this._ref) : super(const ActiveRideState());

  final Ref _ref;

  /// Accept an incoming ride. Sends the `ride:accept` socket event and
  /// awaits the backend's ack. The full ride entity arrives over the
  /// `ride:state` socket event shortly after — until then the slim ride
  /// payload from the request modal is good enough to render the screen.
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
      // Advance immediately to `driver_en_route`. Backend's PATCH is
      // idempotent now, but `RideStageTimeoutService` still auto-cancels
      // rides that sit in `accepted` for >2 minutes — and a real driver
      // takes 5–10 minutes to reach the pickup. Without this kick, the
      // backend cancels the ride out from under us before the driver
      // arrives. The PATCH is fire-and-forget; the resulting `ride:state`
      // snapshot reconciles local state.
      unawaited(markEnRoute());
      return true;
    } on TimeoutException {
      developer.log('acceptRide timed out', name: 'ActiveRide', level: 900);
      state = const ActiveRideState(
        errorMessage: "We didn't hear back from the server. Please try again.",
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

  /// Decline an incoming ride. Fires `ride:decline` to the backend so the
  /// matcher immediately moves on to the next driver instead of waiting
  /// for the acceptance window to expire. Fire-and-forget — the request
  /// screen pops regardless of network state, and the 30 s matcher timeout
  /// is the safety net if the emit never lands.
  void declineRide(String rideId, {String? reason}) {
    try {
      final socket = _ref.read(socketServiceProvider);
      socket.emit('ride:decline', {
        'rideId': rideId,
        if (reason != null) 'reason': reason,
      });
    } catch (e) {
      developer.log('declineRide emit failed: $e',
          name: 'ActiveRide', level: 900);
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
  /// can then read `errorMessage` from state on failure. The backend's
  /// PATCH walks the legal path in one transaction, so a single call from
  /// any forward status to any forward status is valid.
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
      // Include the freshest cached GPS fix on every lifecycle transition.
      // The backend uses the in-progress/start and completion fixes as trail
      // boundaries; live socket heartbeats fill the points between them.
      final position = _ref.read(lastKnownPositionProvider);
      final json = await _ref.read(rideServiceProvider).updateRideStatus(
            ride.id,
            status: next.toJson(),
            currentLat: position?.latitude,
            currentLng: position?.longitude,
          );
      // PATCH response is the full ride snapshot (same shape the
      // `ride:state` socket event carries). Apply it directly so the UI
      // reacts on this round-trip even if the socket event is delayed.
      // The socket listener will arrive a moment later with an identical
      // payload — `applySnapshot` is idempotent.
      final updated = _safeParseRide(json) ?? ride.copyWith(status: next);
      state = state.copyWith(ride: updated, isUpdating: false);
      if (updated.status == RideStatus.completed ||
          updated.status == RideStatus.cancelled) {
        _resumeOnline();
        // Backend's `recordRideCompletion()` writes the Payment row
        // fire-and-forget right after the status flip; bust the driver
        // dashboard caches synchronously here so the home tile reflects
        // it on the next read. The socket `ride:state` listener does
        // the same invalidation, but a driver who drops WS at the
        // moment of completion (mid-ride disconnect grace period) wouldn't
        // get that event — they'd open the home screen and see stale
        // earnings.
        _bustEarningsCaches();
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
      // If the backend says we can't transition, our local copy of the
      // ride is almost certainly stale — most often because the backend
      // auto-cancelled the ride out from under us via a stage timeout
      // and the cancellation broadcast didn't reach this socket. Pull
      // the authoritative state so the screen can react (e.g. navigate
      // away when status is now `cancelled`).
      if (e.errorCode == 'INVALID_STATUS_TRANSITION' ||
          e.errorCode == 'NOT_ASSIGNED_DRIVER' ||
          e.errorCode == 'RIDE_ALREADY_ASSIGNED') {
        unawaited(_refreshFromBackend(ride.id));
      }
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
  /// proper `cancelled` row, then ALWAYS clear local state — even if the
  /// backend refuses (data corruption, network drop) the driver should
  /// still be able to escape the screen rather than be permanently stuck
  /// on a ride they can't progress.
  ///
  /// Returns a [RideCancelOutcome] describing the fee charged to the driver
  /// and whether the backend just suspended the account for excessive
  /// cancellations — so the screen can show a dedicated dialog instead of
  /// silently kicking the driver back to the home map.
  Future<RideCancelOutcome> cancelRide({String? reason}) async {
    final ride = state.ride;
    if (ride == null) {
      clearRide();
      return const RideCancelOutcome();
    }
    state = state.copyWith(isUpdating: true, clearError: true);
    var outcome = const RideCancelOutcome();
    try {
      final result = await _ref.read(rideServiceProvider).cancelRide(
            ride.id,
            reason: reason ?? 'driver_cancelled',
          );
      outcome = RideCancelOutcome(
        feePesewas: (result['cancellationFeePesewas'] as num?)?.toInt() ?? 0,
        driverSuspended: result['driverSuspended'] == true,
        driverNoShow: result['driverNoShow'] == true,
      );
      developer.log(
        'cancelRide PATCH succeeded for ${ride.id} '
        '(fee=${outcome.feePesewas} suspended=${outcome.driverSuspended})',
        name: 'ActiveRide',
      );
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
    return outcome;
  }

  /// Apply a full ride snapshot from a `ride:state` socket event (or any
  /// other authoritative source — REST PATCH response, recovery fetch).
  /// Replaces the local ride wholesale; on terminal states (completed /
  /// cancelled) flips the driver back to `online`.
  ///
  /// Idempotent — re-applying an identical snapshot is a no-op.
  void applySnapshot(Ride snapshot) {
    final current = state.ride;
    if (current != null && current.id != snapshot.id) {
      // Snapshot for a different ride than the one we're tracking — guard
      // against cross-ride leaks (shouldn't happen, but keeps the screen
      // stable if the backend rooms ever cross-talk).
      return;
    }
    // Late terminal echo for a ride we've ALREADY cleared locally. A
    // driver-initiated cancel clears state + navigates home synchronously,
    // then the backend's own `ride:state` (cancelled) lands a second or two
    // later over the socket. Without this guard we'd re-populate `ride` with
    // the cancelled snapshot and bounce the driver back to the active-ride
    // map. Nothing to transition — just make sure we're back online.
    if (current == null &&
        (snapshot.status == RideStatus.completed ||
            snapshot.status == RideStatus.cancelled)) {
      _resumeOnline();
      return;
    }
    // Backend's `ride:state` payload doesn't yet include `stops`; preserve
    // whatever we already have locally so a snapshot doesn't blow away
    // stops that arrived via `ride:route_updated` REST refetch.
    final preserved =
        snapshot.stops.isEmpty && current != null && current.stops.isNotEmpty
            ? snapshot.copyWith(stops: current.stops)
            : snapshot;
    state = state.copyWith(ride: preserved);
    if (preserved.status == RideStatus.completed ||
        preserved.status == RideStatus.cancelled) {
      _resumeOnline();
    }
  }

  /// Restore an active ride from the recovery flow on app start. Same
  /// shape as [applySnapshot] but also flips the provider status to busy
  /// (recovery means we're definitely on a live ride).
  void restore(Ride ride) {
    state = ActiveRideState(ride: ride);
    _setBusy();
    // Tag the ride as already surfaced so the request modal doesn't pop
    // over the active-ride screen if a stale `ride:new` re-broadcast
    // lands while we're recovering. Without this, a force-quit during
    // acceptance could re-show the request modal post-recovery.
    try {
      _ref.read(surfacedRideIdsProvider.notifier).update(
            (s) => {...s, ride.id},
          );
    } catch (_) {}
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

  /// Invalidates every earnings-flavoured cache so the next read returns
  /// fresh server data. Called whenever a ride flips to `completed`,
  /// since the backend's `recordRideCompletion` inserts a Payment row
  /// (or marks an existing one terminal) — the dashboard's
  /// `FutureProvider`s would otherwise keep serving stale figures.
  /// Mirrors the artisan-side `_bustEarningsCaches` in
  /// `active_job_provider.dart`. Wrapped in try/catch so a missing
  /// provider in tests doesn't crash the transition.
  void _bustEarningsCaches() {
    try {
      _ref.invalidate(todayCardProvider);
      _ref.invalidate(earningsSummaryProvider);
      _ref.invalidate(earningsReportProvider);
      _ref.invalidate(activeTodayCardProvider);
      _ref.invalidate(payoutsProvider);
      _ref.invalidate(providerRatingsProvider);
      _ref.invalidate(driverTripsProvider);
    } catch (_) {
      // Providers may not be mounted yet (tests, fresh-launch); harmless
      // if they aren't, we just lose the eager refetch.
    }
  }

  /// Pull the authoritative ride state from REST and apply it via
  /// [applySnapshot]. Called when a PATCH bounces back with a code that
  /// implies our local state has drifted (ride auto-cancelled by the
  /// backend's stage-timeout cron, another driver reassigned, etc.).
  /// Failures are non-fatal — the user sees the original error message.
  Future<void> _refreshFromBackend(String rideId) async {
    try {
      final json = await _ref.read(rideServiceProvider).getRide(rideId);
      final fresh = Ride.fromJson(json);
      if (state.ride?.id != rideId) return;
      applySnapshot(fresh);
    } catch (e) {
      developer.log('refreshFromBackend failed: $e',
          name: 'ActiveRide', level: 800);
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
