import 'dart:async';
import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../../core/providers/location_degradation_provider.dart';
import '../../../core/providers/availability_reconciliation_controller.dart';
import '../../../core/providers/socket_provider.dart';
import '../../../core/services/ride_offer_receipt_service.dart';
import '../../../core/services/lifecycle_location_service.dart';
import '../../earnings/providers/earnings_providers.dart';
import '../../earnings/providers/ratings_provider.dart';
import '../../trips/providers/driver_trips_provider.dart';

// The incoming ride/job request providers are in
// core/providers/socket_provider.dart — driven by Socket.IO events.

/// Ride request currently visible on the full-screen request route.
///
/// FCM taps, socket events and pending-request recovery can all fire within a
/// few hundred milliseconds of each other after a background wake. This shared
/// marker lets those entry points reuse/ignore the existing request screen
/// instead of stacking duplicate `/ride-request` routes for the same ride.
final visibleRideRequestIdProvider = StateProvider<String?>((_) => null);

/// Exact widget instance that currently owns [visibleRideRequestIdProvider].
///
/// A request route can be replaced with a freshly hydrated route for the same
/// ride id. The id alone cannot distinguish the outgoing screen from its
/// successor, so dispose-time cleanup must be conditional on this token.
class VisibleRideRequestOwner {
  const VisibleRideRequestOwner({
    required this.rideId,
    required this.token,
  });

  final String rideId;
  final Object token;
}

final visibleRideRequestOwnerProvider =
    StateProvider<VisibleRideRequestOwner?>((_) => null);

/// Ride request ids currently being hydrated/navigated from a notification tap.
///
/// Used as a short-lived guard so the foreground recovery bridge does not
/// surface the same request while the tap handler is still fetching the full
/// ride payload.
final rideRequestNavigationInFlightProvider =
    StateProvider<Set<String>>((_) => <String>{});

class RideOfferDismissal {
  const RideOfferDismissal({
    required this.rideId,
    required this.reason,
  });

  final String rideId;
  final String reason;
}

/// Terminal signal for a pre-acceptance ride offer already visible on the
/// full-screen request route. Clearing the incoming payload alone cannot pop a
/// route that received an immutable Ride through GoRouter.
final rideOfferDismissalProvider =
    StateProvider<RideOfferDismissal?>((_) => null);

bool isConfirmedRideAcceptResponse(Object? raw, String rideId) {
  if (raw is! Map) return false;
  return raw['rideId']?.toString() == rideId &&
      raw['status']?.toString() == 'accepted';
}

/// Best-known deadline for each incoming ride request.
///
/// The backend's pending-request endpoint can return `expiresAt`; FCM/socket
/// payloads may also carry it. The request screen falls back to
/// `ride.createdAt + 30s` when no explicit deadline is available.
final rideRequestDeadlineByIdProvider =
    StateProvider<Map<String, DateTime>>((_) => <String, DateTime>{});

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

/// Outcome of a driver-side ride cancellation. Consequence fields are rendered
/// only when the backend explicitly reports their state. An omitted flag from
/// an older backend remains unknown so the app never displays a false pause.
class RideCancelOutcome {
  const RideCancelOutcome({
    this.cancelled = false,
    this.feePesewas = 0,
    this.driverSuspended = false,
    this.driverNoShow = false,
    this.cancellationConsequencesApplied,
    this.notice,
  });

  /// True only when the backend accepted the cancellation and the local ride
  /// state has been cleared.
  final bool cancelled;
  final int feePesewas;
  final bool driverSuspended;

  /// True when the backend treated this as a client no-show (driver waited out
  /// the free window before cancelling) — no rating/counter penalty applied.
  final bool driverNoShow;
  final bool? cancellationConsequencesApplied;
  final String? notice;

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
    _ref.read(systemTelemetryProvider).trackAction(
          'driver_accept_ride_requested',
          correlationId: ride.id,
        );
    // Do not expose the pre-acceptance `requested` ride through
    // [activeRideProvider]. The shell-level recovery listener treats a
    // non-null ride here as something it may route to /active-ride; putting
    // a still-requested ride in this slot can bounce the driver to "No active
    // ride" before the backend has actually assigned them.
    state = const ActiveRideState(isUpdating: true);
    try {
      final offerId = _ref.read(rideOfferIdByRideProvider)[ride.id];
      if (offerId == null || offerId.isEmpty) {
        state = const ActiveRideState(
          errorMessage: 'This ride offer is still syncing. Please try again.',
        );
        return false;
      }
      final socket = _ref.read(socketServiceProvider);
      Map<String, dynamic>? ackMap;
      try {
        final ack = await socket.emitWithAck(
          'ride:accept',
          {'rideId': ride.id, 'offerId': offerId},
        );
        developer.log('ride:accept ack: $ack', name: 'ActiveRide');
        ackMap = ack is Map ? Map<String, dynamic>.from(ack) : null;
      } on TimeoutException catch (error) {
        developer.log(
          'ride:accept socket ack timed out; reconciling over REST: $error',
          name: 'ActiveRide',
          level: 900,
        );
      } on StateError catch (error) {
        developer.log(
          'ride:accept socket unavailable; reconciling over REST: $error',
          name: 'ActiveRide',
          level: 900,
        );
      }

      // Backend ack returns either `driverPayload` (success) or an
      // exception event. On success the response is a Map containing at
      // least `rideId` and `status: 'accepted'`. Anything else is treated
      // as a failure so the user sees a clear error instead of a stuck
      // active-ride screen.
      final ackError = ackMap?['error'] as String?;
      if (ackError != null) {
        state = ActiveRideState(errorMessage: _friendlyAckError(ackError));
        return false;
      }

      final socketConfirmed = isConfirmedRideAcceptResponse(ackMap, ride.id);
      if (!socketConfirmed) {
        final rest = await _ref
            .read(rideServiceProvider)
            .acceptRideRequest(ride.id, offerId: offerId);
        if (!isConfirmedRideAcceptResponse(rest, ride.id)) {
          state = const ActiveRideState(
            errorMessage:
                "We couldn't confirm the ride assignment. Please refresh and try again.",
          );
          return false;
        }
      }

      state = ActiveRideState(
        ride: ride.copyWith(status: RideStatus.accepted),
      );
      _clearOfferIdentity(ride.id, offerId);
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
    } on ApiException catch (e) {
      developer.log('acceptRide API error: $e', name: 'ActiveRide', level: 900);
      state = ActiveRideState(
        errorMessage: e.errorCode == null
            ? userSafeApiErrorMessage(
                e,
                fallback: "Couldn't accept the ride. Please try again.",
                conflictMessage:
                    'This ride offer changed. Refresh and try again.',
              )
            : _friendlyAckError(e.errorCode!),
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

  /// Accept an offer selected from a native notification/overlay action.
  ///
  /// A terminated-app launch has no connected socket yet, so this uses the
  /// REST equivalent, then hydrates the authoritative active ride before the
  /// router opens `/active-ride`.
  Future<bool> acceptRideFromNotification(
    String rideId, {
    String? offerId,
  }) async {
    if (state.isUpdating || rideId.isEmpty) return false;
    state = const ActiveRideState(isUpdating: true);
    try {
      final activeOfferId =
          offerId ?? _ref.read(rideOfferIdByRideProvider)[rideId];
      if (activeOfferId == null || activeOfferId.isEmpty) {
        state = const ActiveRideState(
          errorMessage: 'This ride offer is no longer actionable.',
        );
        return false;
      }
      final service = _ref.read(rideServiceProvider);
      await service.acceptRideRequest(rideId, offerId: activeOfferId);
      final raw = await service.getMyActiveRide();
      if (raw == null) {
        state = const ActiveRideState(
          errorMessage: 'Ride accepted, but its details are still loading.',
        );
        return false;
      }
      final ride = Ride.fromJson(raw);
      if (ride.id != rideId || !ride.status.isActive) {
        state = const ActiveRideState(
          errorMessage: 'This ride is no longer available.',
        );
        return false;
      }
      restore(ride);
      _clearOfferIdentity(rideId, activeOfferId);
      unawaited(markEnRoute());
      return true;
    } on ApiException catch (e) {
      developer.log(
        'notification ride accept failed: ${e.errorCode} — ${e.message}',
        name: 'ActiveRide',
        level: 900,
      );
      state = ActiveRideState(
        errorMessage: _friendlyAckError(e.errorCode ?? ''),
      );
      return false;
    } catch (e) {
      developer.log(
        'notification ride accept crashed: $e',
        name: 'ActiveRide',
        level: 1000,
      );
      state = const ActiveRideState(
        errorMessage: 'Could not accept the ride. Please try again.',
      );
      return false;
    }
  }

  /// Skip an offer from a native notification/overlay action. REST is used so
  /// the matcher can advance even before Socket.IO reconnects on cold start.
  Future<bool> declineRideFromNotification(
    String rideId, {
    String? offerId,
    String reason = 'notification_skip',
  }) async {
    if (rideId.isEmpty) return false;
    try {
      final activeOfferId =
          offerId ?? _ref.read(rideOfferIdByRideProvider)[rideId];
      if (activeOfferId == null || activeOfferId.isEmpty) return false;
      await _ref.read(rideServiceProvider).declineRideRequest(
            rideId,
            offerId: activeOfferId,
            reason: reason,
          );
      _clearOfferIdentity(rideId, activeOfferId);
      return true;
    } on ApiException catch (e) {
      developer.log(
        'notification ride decline failed: ${e.errorCode} — ${e.message}',
        name: 'ActiveRide',
        level: 900,
      );
      return false;
    } catch (e) {
      developer.log(
        'notification ride decline crashed: $e',
        name: 'ActiveRide',
        level: 1000,
      );
      return false;
    }
  }

  /// Decline an incoming ride. Fires `ride:decline` to the backend so the
  /// matcher immediately moves on to the next driver instead of waiting
  /// for the acceptance window to expire. The screen can pop immediately,
  /// while this reconciles a lost socket acknowledgement over idempotent REST.
  void declineRide(String rideId, {String? reason, String? offerId}) {
    final activeOfferId =
        offerId ?? _ref.read(rideOfferIdByRideProvider)[rideId];
    if (activeOfferId == null || activeOfferId.isEmpty) return;
    unawaited(
      _declineRideAuthoritatively(
        rideId,
        activeOfferId,
        reason,
      ),
    );
  }

  Future<void> _declineRideAuthoritatively(
    String rideId,
    String offerId,
    String? reason,
  ) async {
    try {
      final socket = _ref.read(socketServiceProvider);
      final ack = await socket.emitWithAck(
          'ride:decline',
          {
            'rideId': rideId,
            'offerId': offerId,
            if (reason != null) 'reason': reason,
          },
          timeout: const Duration(seconds: 3));
      if (ack is Map && ack['error'] != null) return;
      if (ack is Map && ack['acknowledged'] == true) {
        _clearOfferIdentity(rideId, offerId);
        return;
      }
    } catch (error) {
      developer.log(
        'ride:decline socket path failed; reconciling over REST: $error',
        name: 'ActiveRide',
        level: 900,
      );
    }
    try {
      await _ref.read(rideServiceProvider).declineRideRequest(
            rideId,
            offerId: offerId,
            reason: reason,
          );
      _clearOfferIdentity(rideId, offerId);
    } catch (error) {
      developer.log(
        'ride:decline REST fallback failed: $error',
        name: 'ActiveRide',
        level: 900,
      );
    }
  }

  void _clearOfferIdentity(String rideId, String offerId) {
    _ref.read(rideOfferIdByRideProvider.notifier).update(
          (offers) => {...offers}..remove(rideId),
        );
    _ref.read(rideRequestDeadlineByIdProvider.notifier).update(
          (deadlines) => {...deadlines}..remove(rideId),
        );
    unawaited(clearStoredRideOffer(offerId));
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
      final needsLifecycleFix = next == RideStatus.arrived ||
          next == RideStatus.inProgress ||
          next == RideStatus.completed;
      final position = needsLifecycleFix
          ? await _ref
              .read(lifecycleLocationServiceProvider)
              .obtain(_ref.read(lastKnownPositionProvider))
          : null;
      if (position != null) {
        _ref.read(lastKnownPositionProvider.notifier).state = position;
      }
      final json = await _ref.read(rideServiceProvider).updateRideStatus(
            ride.id,
            status: next.toJson(),
            currentLat: position?.latitude,
            currentLng: position?.longitude,
            accuracyMeters: position?.accuracy,
            capturedAt: position?.timestamp,
          );
      // PATCH response is the full ride snapshot (same shape the
      // `ride:state` socket event carries). Apply it directly so the UI
      // reacts on this round-trip even if the socket event is delayed.
      // The socket listener will arrive a moment later with an identical
      // payload — `applySnapshot` is idempotent.
      var updated = _safeParseRide(json);
      if (updated == null ||
          updated.id != ride.id ||
          !_hasReachedRideStatus(updated.status, next)) {
        developer.log(
          'Ride transition response was not authoritative for ${ride.id}; '
          'reading the ride back before changing local status',
          name: 'ActiveRide',
          level: 900,
        );
        updated = await _refreshFromBackend(ride.id);
      }
      if (updated == null ||
          updated.id != ride.id ||
          !_hasReachedRideStatus(updated.status, next)) {
        state = state.copyWith(
          isUpdating: false,
          errorMessage: updated?.status == RideStatus.cancelled
              ? 'This ride was cancelled before the update could finish.'
              : "We couldn't confirm the ride update. Keep this ride open while we check again.",
        );
        return false;
      }
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
    } on LifecycleLocationException catch (e) {
      state = state.copyWith(
        isUpdating: false,
        errorMessage: e.message,
      );
      return false;
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
          e.errorCode == 'LIFECYCLE_CHECKPOINT_REQUIRED' ||
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

  /// Cancel the active ride.
  ///
  /// Only clears local state after the backend confirms the ride is cancelled.
  /// That is deliberate: once a trip is already `in_progress`, the backend now
  /// rejects normal cancellation, and clearing local state anyway would make the
  /// driver app *look* cancelled while the rider/backend still have an active
  /// trip. Real in-trip exceptions should go through completion, SOS/support,
  /// or admin force-complete/force-cancel.
  ///
  /// Returns a [RideCancelOutcome] describing the fee charged to the driver
  /// and whether the backend just suspended the account for excessive
  /// cancellations — so the screen can show a dedicated dialog instead of
  /// silently kicking the driver back to the home map.
  Future<RideCancelOutcome> cancelRide({String? reason}) async {
    _ref.read(systemTelemetryProvider).trackAction(
      'driver_cancel_ride_requested',
      correlationId: state.ride?.id,
      metadata: {'reasonSelected': reason?.isNotEmpty == true},
    );
    final ride = state.ride;
    if (ride == null) {
      clearRide();
      return const RideCancelOutcome();
    }
    if (ride.status == RideStatus.inProgress) {
      state = state.copyWith(
        isUpdating: false,
        errorMessage:
            'This trip has already started. End the trip normally or contact support.',
      );
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
        cancelled: true,
        feePesewas: (result['cancellationFeePesewas'] as num?)?.toInt() ?? 0,
        driverSuspended: result['driverSuspended'] == true,
        driverNoShow: result['driverNoShow'] == true,
        cancellationConsequencesApplied:
            result.containsKey('cancellationConsequencesApplied')
                ? result['cancellationConsequencesApplied'] == true
                : null,
        notice: result['notice'] as String?,
      );
      developer.log(
        'cancelRide PATCH succeeded for ${ride.id} '
        '(fee=${outcome.feePesewas} suspended=${outcome.driverSuspended})',
        name: 'ActiveRide',
      );
    } on ApiException catch (e) {
      developer.log(
        'cancelRide PATCH failed: ${e.errorCode} — ${e.message} '
        '(reconciling authoritative ride)',
        name: 'ActiveRide',
        level: 900,
      );
      final fresh = await _refreshFromBackend(ride.id);
      if (fresh?.status == RideStatus.cancelled) {
        clearRide();
        return const RideCancelOutcome(
          cancelled: true,
          notice: 'Ride cancellation confirmed.',
        );
      }
      state = state.copyWith(
        isUpdating: false,
        errorMessage: _cancellationFailureMessage(e, fresh?.status),
      );
      return outcome;
    } catch (e) {
      developer.log(
        'cancelRide crashed: $e (reconciling authoritative ride)',
        name: 'ActiveRide',
        level: 1000,
      );
      final fresh = await _refreshFromBackend(ride.id);
      if (fresh?.status == RideStatus.cancelled) {
        clearRide();
        return const RideCancelOutcome(
          cancelled: true,
          notice: 'Ride cancellation confirmed.',
        );
      }
      state = state.copyWith(
        isUpdating: false,
        errorMessage: fresh == null
            ? "We couldn't confirm whether the ride was cancelled. Keep this ride open while we check again."
            : _cancellationFailureMessage(null, fresh.status),
      );
      return outcome;
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
    if (current == null && snapshot.status == RideStatus.requested) {
      // A requested ride is still an offer, not an active ride for this
      // driver. Keep it out of the active slot so the UI doesn't open the
      // active-ride screen before the driver has successfully accepted.
      developer.log(
        'Ignoring requested ride snapshot for active slot: ${snapshot.id}',
        name: 'ActiveRide',
        level: 800,
      );
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

  /// Apply a slim remote cancellation event when the full `ride:state`
  /// snapshot is unavailable or arrives later.
  ///
  /// The ride-id guard is essential: a delayed push/event for an earlier ride
  /// must never clear or cancel a newer active ride.
  bool applyRemoteCancellation(String rideId) {
    final current = state.ride;
    if (rideId.isEmpty || current == null || current.id != rideId) return false;
    if (current.status == RideStatus.cancelled) return true;
    applySnapshot(current.copyWith(status: RideStatus.cancelled));
    return true;
  }

  /// Clear a matching ride after a terminal FCM tap/foreground push.
  /// Returns whether the supplied id owned the active slot.
  bool clearRideIfMatches(String? rideId) {
    final current = state.ride;
    if (rideId == null || rideId.isEmpty || current?.id != rideId) {
      return false;
    }
    clearRide();
    return true;
  }

  /// Refresh the locally-tracked ride from its authoritative REST snapshot.
  ///
  /// This runs when Socket.IO reconnects. If a rider cancelled while the app
  /// was backgrounded, the socket room no longer has a live ride to restore;
  /// fetching by id still returns the terminal snapshot and lets the UI leave
  /// the stale active-ride screen without requiring an app restart.
  Future<void> reconcileTrackedRide() async {
    final tracked = state.ride;
    if (tracked == null) return;
    try {
      final raw = await _ref.read(rideServiceProvider).getRide(tracked.id);
      final snapshot = Ride.fromJson(raw);
      final current = state.ride;
      if (current == null || current.id != tracked.id) return;
      if (snapshot.status == RideStatus.requested) return;
      applySnapshot(snapshot);
    } on ApiException catch (error) {
      developer.log(
        'active ride reconcile failed: ${error.errorCode} — ${error.message}',
        name: 'ActiveRide',
        level: 900,
      );
      // An assigned ride should remain readable after cancellation. A 404
      // means the local active slot is definitely stale; drive the same
      // terminal transition used by socket/FCM cancellation.
      if (error.statusCode == 404) applyRemoteCancellation(tracked.id);
    } catch (error) {
      developer.log(
        'active ride reconcile crashed: $error',
        name: 'ActiveRide',
        level: 900,
      );
    }
  }

  /// Restore an active ride from the recovery flow on app start. Same
  /// shape as [applySnapshot] but also flips the provider status to busy
  /// (recovery means we're definitely on a live ride).
  void restore(Ride ride) {
    if (!ride.status.isActive) {
      developer.log(
        'Ignoring non-active ride restore: ${ride.id} (${ride.status})',
        name: 'ActiveRide',
        level: 800,
      );
      return;
    }
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
      final locationRecoveryRequired =
          _ref.read(providerLocationDegradationProvider).isDegraded;
      _ref.read(providerStatusProvider.notifier).finishActiveWork(
            locationRecoveryRequired: locationRecoveryRequired,
          );
      unawaited(
        _ref
            .read(availabilityReconciliationControllerProvider)
            .reconcile(trigger: 'driver_work_finished'),
      );
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
  Future<Ride?> _refreshFromBackend(String rideId) async {
    try {
      final json = await _ref.read(rideServiceProvider).getRide(rideId);
      final fresh = Ride.fromJson(json);
      if (state.ride?.id != rideId) return fresh;
      applySnapshot(fresh);
      return fresh;
    } catch (e) {
      developer.log('refreshFromBackend failed: $e',
          name: 'ActiveRide', level: 800);
      return null;
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
      case 'LIFECYCLE_CHECKPOINT_REQUIRED':
        return 'Complete arrival, trip start, and trip end as separate steps.';
      case 'LIFECYCLE_LOCATION_REQUIRED':
        return 'Get your current GPS location before updating this ride.';
      case 'GPS_FIX_STALE':
        return 'MyShop needs a GPS fix from the last 15 seconds. Try again.';
      case 'GPS_ACCURACY_REQUIRED':
        return 'GPS accuracy is too low. Move to an open area and try again.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: 'Could not update the ride. Please try again.',
          conflictMessage:
              'The ride changed before the update completed. Refresh and try again.',
        );
    }
  }

  String _cancellationFailureMessage(
    ApiException? error,
    RideStatus? authoritativeStatus,
  ) {
    if (authoritativeStatus == RideStatus.inProgress) {
      return 'This trip has already started. End the trip normally or contact support.';
    }
    if (authoritativeStatus == RideStatus.completed) {
      return 'This ride has already ended and can no longer be cancelled.';
    }
    return switch (error?.errorCode) {
      'RIDE_NOT_FOUND' =>
        'This ride could not be found. Refresh your trips and try again.',
      'NOT_YOUR_RIDE' ||
      'PROFILE_REQUIRED' =>
        'This driver account is not allowed to cancel the ride.',
      'RIDE_NOT_CANCELLABLE' => 'This ride can no longer be cancelled.',
      'RATE_LIMITED' ||
      'TOO_MANY_REQUESTS' =>
        'Too many attempts. Wait a moment, then try again.',
      _ => 'Could not cancel the ride. Please try again.',
    };
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

bool _hasReachedRideStatus(RideStatus current, RideStatus target) {
  if (current == RideStatus.cancelled) return false;
  const rank = <RideStatus, int>{
    RideStatus.requested: 0,
    RideStatus.accepted: 1,
    RideStatus.driverEnRoute: 2,
    RideStatus.arrived: 3,
    RideStatus.inProgress: 4,
    RideStatus.completed: 5,
  };
  return (rank[current] ?? -1) >= (rank[target] ?? 999);
}

final activeRideProvider =
    StateNotifierProvider<ActiveRideNotifier, ActiveRideState>(
  (ref) => ActiveRideNotifier(ref),
);
