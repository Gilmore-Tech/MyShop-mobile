import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import '../../app/router.dart' show goRouterProvider;
import '../../features/artisan_home/providers/active_job_provider.dart';
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_home/providers/live_job_feed_provider.dart';
import '../../features/artisan_home/widgets/rate_client_sheet.dart';
import '../../features/artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/auth/providers/current_user_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/earnings/providers/earnings_providers.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../../features/driver_home/widgets/rate_passenger_sheet.dart';
import '../../features/trips/providers/driver_trips_provider.dart';
import 'availability_controller.dart';
import 'availability_reconciliation_controller.dart';
import 'provider_status_provider.dart';
import 'provider_location_session_provider.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import 'nav_badge_provider.dart';
import '../di/providers.dart';
import '../services/incoming_request_overlay_presenter.dart';
import '../services/local_notification_service.dart';
import '../services/ride_cancellation_notice.dart';
import '../services/ride_offer_receipt_service.dart';

/// Provides the [SocketService] singleton for the app.
///
/// Refresh failures are handled by the shared [TokenRefresher]
/// (constructed inside `createDioClient`), which fires the
/// app-level `onForceLogout` set in [dioClientProvider] — that
/// transitions auth state to unauthenticated and the
/// [logoutCleanupBridgeProvider] picks up from there
/// (socket dispose, online flag → offline, ride/job state reset).
/// The socket service itself no longer carries an onForceLogout —
/// kept consistent with the REST path.
final socketServiceProvider = Provider<SocketService>((ref) {
  ref.watch(currentAuthSessionIdentityProvider);
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final tokenRefresher = ref.watch(tokenRefresherProvider);
  final service = SocketService(
    config: config,
    tokenStorage: tokenStorage,
    tokenRefresher: tokenRefresher,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Incoming ride request for drivers — populated by Socket.IO events.
final incomingRideRequestProvider = StateProvider<Ride?>((ref) => null);

/// IDs of ride requests we've already surfaced this session — prevents the
/// request screen from re-stacking when the backend re-broadcasts the same
/// ride to the driver before they accept/decline. Cleared on logout so a
/// returning driver isn't permanently blind to old ride IDs.
final surfacedRideIdsProvider = StateProvider<Set<String>>((_) => <String>{});

/// Authoritative offer identity for each surfaced ride. Accept/decline must
/// send this id; a ride id alone cannot prove which sequential offer is live.
final rideOfferIdByRideProvider =
    StateProvider<Map<String, String>>((_) => <String, String>{});

@visibleForTesting
String? rideCancellationIdFromEvent(
  Object? data, {
  bool requireCancelledStatus = false,
}) {
  if (data is! Map) return null;
  final rideId = (data['rideId'] ?? data['id'])?.toString().trim();
  if (rideId == null || rideId.isEmpty) return null;
  if (requireCancelledStatus &&
      data['status']?.toString().trim().toLowerCase() != 'cancelled') {
    return null;
  }
  return rideId;
}

/// Incoming job request for artisans — populated by Socket.IO events.
final incomingJobRequestProvider = StateProvider<Job?>((ref) => null);

/// Job id currently visible on the full `/job-request` details route.
///
/// Mirrors [visibleRideRequestIdProvider] on the driver side: FCM taps,
/// socket events and the incoming-job modal can all fire within moments of
/// each other after a background wake. This marker lets the notification-tap
/// handler keep the already-open details screen instead of tearing it down
/// and re-pushing a stub that re-fetches the same job (which reads as
/// details → loading → details to the artisan).
final visibleJobRequestIdProvider = StateProvider<String?>((_) => null);

/// True while the Socket.IO connection is open.
/// Useful for showing a live indicator on the home screen.
final socketConnectedProvider = StateProvider<bool>((ref) => false);

/// The last event received from the socket — helpful for debugging.
/// Format: `"{event-name}: {truncated-data}"`.
final lastSocketEventProvider = StateProvider<String?>((ref) => null);

/// Manages the Socket.IO connection lifecycle.
///
/// Connects whenever the provider is `online` OR `busy` (the latter covers
/// the recovered-active-ride case where the driver is mid-trip and must keep
/// receiving `ride:state` snapshots and pushing the location heartbeat).
/// Disconnects only on `offline`. Gating on `status.isOnline` would have
/// torn the socket down the moment a recovered ride flipped status to
/// `busy`, leaving the rider's marker frozen and the driver invisible to
/// completion broadcasts.
final socketConnectionProvider = Provider<void>((ref) {
  final status = ref.watch(providerStatusProvider);
  final socket = ref.read(socketServiceProvider);

  if (status == DriverStatus.offline) {
    socket.disconnect();
  } else {
    _connectAndListen(ref, socket);
  }
});

/// Pipes the location stream into the driver socket while Socket.IO is open.
///
/// Socket emit = real-time, low-latency feed for rider/admin maps.
/// REST writes = owned by the background location sync provider, which runs without
/// depending on socket connectivity so background/screen-off continuity is not
/// tied to the foreground WebSocket.
///
/// Watched by the shell — activates whenever the provider is online.
final locationSocketBridgeProvider = Provider<void>((ref) {
  // Gate on auth state first — even if `providerStatus` is stale (e.g. a
  // logout race that hasn't flipped status yet), a null user means there
  // is no token to attach and every heartbeat would 401-storm. This is
  // defence-in-depth alongside the force-logout cascade in
  // `socketServiceProvider`.
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    debugPrint('[LOC] bridge: unauthenticated — idle');
    return;
  }

  final status = ref.watch(providerStatusProvider);
  // Run while online OR busy. During an active ride (busy) the rider's map
  // depends on this heartbeat to track the car; if we gated on `isOnline`
  // alone the marker would freeze the moment the trip moved to `busy`.
  if (status == DriverStatus.offline) {
    debugPrint('[LOC] bridge: status=$status — idle');
    return;
  }

  final connected = ref.watch(socketConnectedProvider);
  if (!connected) {
    debugPrint('[LOC] bridge: online but socket not connected — waiting');
    return;
  }

  final socket = ref.read(socketServiceProvider);
  final isArtisan = ref.read(providerTypeProvider).isArtisan;
  final container = ref.container;
  var disposed = false;
  DateTime? lastEmittedCapturedAt;
  ref.onDispose(() => disposed = true);
  debugPrint('[LOC] bridge: active (role=${isArtisan ? 'artisan' : 'driver'})'
      ' — listening for fixes');

  // Driver-only: emit `driver:location:update` over the socket for the live
  // map path. The backend has no artisan equivalent — every artisan emit
  // returns DRIVER_PROFILE_REQUIRED, which floods the socket with exception
  // events. Artisans use the REST path exclusively via background sync, and the
  // matcher reads their position from the PostGIS table the REST writer updates.
  void emitDriverLocation(Position pos) {
    if (disposed || isArtisan) return;
    if (!isOnlineLocationFixAcceptable(pos)) return;
    final capturedAt = pos.timestamp.toUtc();
    final previousCapturedAt = lastEmittedCapturedAt;
    if (previousCapturedAt != null && !capturedAt.isAfter(previousCapturedAt)) {
      return;
    }
    final locationSession = container.read(providerLocationSessionProvider);
    if (locationSession == null) return;
    final sampleSequence =
        container.read(providerLocationSessionProvider.notifier).nextSequence();
    socket.emit('driver:location:update', {
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracyMeters': pos.accuracy,
      'recordedAt': pos.timestamp.toIso8601String(),
      'sampleSequence': sampleSequence,
      'status': 'online',
    });
    lastEmittedCapturedAt = capturedAt;
  }

  // Socket heartbeat: re-emit the last-known fix every 4s while connected so a
  // stationary driver still advances foreground rider/admin maps. Durable REST
  // heartbeat and trip trail persistence live in backgroundLocationSyncProvider.
  final heartbeat = Timer.periodic(const Duration(seconds: 4), (_) {
    if (disposed) return;
    final pos = container.read(lastKnownPositionProvider);
    if (pos == null) return;
    emitDriverLocation(pos);
  });
  ref.onDispose(heartbeat.cancel);

  // Kick the heartbeat once immediately if we already have a cached fix —
  // otherwise the backend would wait up to 4s before seeing the driver,
  // and the rider's matcher could miss them on a freshly-online driver.
  final cached = container.read(lastKnownPositionProvider);
  if (cached != null) {
    // This provider may itself be created during a widget/provider build. A
    // synchronous emit reserves a sequence by mutating
    // providerLocationSessionProvider while Riverpod is still initializing
    // this bridge, which is forbidden and crashes the first Online frame.
    // Defer the cached-fix emit until the current provider build has completed.
    Timer.run(() => emitDriverLocation(cached));
  } else {
    // No cached fix yet (e.g. recovered into busy on a fresh launch where
    // the warm-up hadn't settled). Pull one synchronously so the matcher
    // and the rider's marker have a starting point — without this, a
    // freshly-recovered driver is invisible until the position stream
    // produces its first emission.
    Future<void>(() async {
      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (disposed) return;
        container.read(lastKnownPositionProvider.notifier).state = fresh;
        emitDriverLocation(fresh);
      } catch (e) {
        debugPrint('[LOC] bridge: cold-fix fetch failed: $e');
      }
    });
  }

  // Listen to the existing position stream so the cached fix advances as
  // the phone moves. Socket-only — the heartbeat is the single REST writer.
  //
  // No `fireImmediately`: a synchronous fire would mutate
  // `lastKnownPositionProvider` while this bridge provider is still
  // initializing, which Riverpod asserts against. The cold-start path
  // above (cached read + Geolocator fallback) already seeds the first
  // fix; this listener only needs to handle subsequent stream emissions.
  ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
    next.when(
      data: (position) {
        if (disposed) return;
        container.read(lastKnownPositionProvider.notifier).state = position;

        // Socket emit on every fix is cheap and gives the matcher fresh
        // coords between heartbeat ticks while the driver is moving.
        emitDriverLocation(position);
      },
      loading: () => debugPrint('[LOC] bridge: stream loading — no fix yet'),
      error: (e, _) => debugPrint('[LOC] bridge: stream error — $e'),
    );
  });
});

/// Bookings (job/ride) for which a rating sheet has already been
/// opened in this app session. Promoted to file-scope so every path
/// that can pop a rating sheet — the socket `rating:prompt` handler
/// here, AND the active-screen completion listeners (e.g.
/// `_ActiveJobScreenState._maybeShowRateClientSheet`) — share one
/// dedup set. Without this, an artisan still on /active-job when the
/// job hits `completed` saw two stacked sheets: one from the screen's
/// status listener, one from the socket event a moment later.
///
/// File-scope (not closure-local) is also what kept the original
/// dedup alive across socket reconnects.
final ratingSheetShownFor = <String>{};

void _connectAndListen(Ref ref, SocketService socket) {
  // Long-lived socket listeners outlive any single `socketConnectionProvider`
  // rebuild — when `providerStatusProvider` flips (online → busy on accept,
  // for example) Riverpod invalidates this provider, but the socket keeps
  // firing into the OLD listener until `attachHandlers` reruns. Using
  // `ref.read` inside those callbacks during the transition window throws
  // `_didChangeDependency` assertions. Reads via `ref.container` skip that
  // tracking and always hit the live state, which is what we want for
  // event-driven mutations like "ride accepted → set incomingRideRequest".
  // Keep `ref.onDispose` / `ref.listen` / `ref.watch` as-is — those belong
  // to the synchronous provider body, not the async listener closures.

  // Mirror connection state for the UI.
  final sub = socket.connectionStream.listen((connected) {
    ref.container.read(socketConnectedProvider.notifier).state = connected;
  });
  ref.onDispose(sub.cancel);

  // Attach (and re-attach, on every reconnect) every domain handler.
  // The lifecycle observer calls `socket.connect()` directly on resume,
  // which disposes the underlying io.Socket and creates a fresh one —
  // any handler that was bound only inside the original `connect().then(...)`
  // chain would silently disappear. Routing attachment through the
  // service's `onAfterCreate` hook guarantees re-binding on every fresh
  // socket; the `off+on` pattern below keeps it idempotent if it ever
  // runs twice against the same socket.
  void attachHandlers() {
    debugPrint('[WS] (re-)attaching domain event handlers');

    // Mirror every incoming event into a state provider for visual debugging.
    socket.onAnyEvent((event, data) {
      final preview = data.toString();
      final trimmed =
          preview.length > 200 ? '${preview.substring(0, 200)}…' : preview;
      ref.container.read(lastSocketEventProvider.notifier).state =
          '$event: $trimmed';
    });

    // The backend heartbeat sweeper is authoritative for idle availability.
    // Do not trust a potentially delayed event payload directly: fetch the
    // current snapshot so a stale forced-offline emit cannot undo a newer
    // successful online transition. Active-work state is left to its
    // dedicated ride/job recovery path.
    void handleForcedOffline(dynamic _) {
      unawaited(
        ref.container
            .read(availabilityReconciliationControllerProvider)
            .reconcile(trigger: 'forced_offline_event'),
      );
    }

    socket
      ..off('availability:forced_offline')
      ..on('availability:forced_offline', handleForcedOffline);

    void handleLocationAuthorityChanged(dynamic _) {
      unawaited(
        ref.container
            .read(availabilityReconciliationControllerProvider)
            .reconcile(trigger: 'location_authority_event'),
      );
    }

    socket
      ..off('availability:location_degraded')
      ..off('availability:location_recovered')
      ..off('availability:location_escalated')
      ..on('availability:location_degraded', handleLocationAuthorityChanged)
      ..on('availability:location_recovered', handleLocationAuthorityChanged)
      ..on('availability:location_escalated', handleLocationAuthorityChanged);

    // Listen for incoming ride requests (driver) — new + legacy event names
    Future<void> receiveRide(dynamic data) async {
      if (data is Map) {
        debugPrint(
          '[WS] Received ride event id=${data['id'] ?? data['rideId']} '
          'keys=${data.keys.join(',')}',
        );
      } else {
        debugPrint('[WS] Received ride event type=${data.runtimeType}');
      }
      if (data is Map) {
        try {
          final delivery = Map<String, dynamic>.from(data);
          final received = await acknowledgeRideOfferWithSocket(
            payload: delivery,
            socket: socket,
            rides: ref.container.read(rideServiceProvider),
          );
          if (received == null) {
            debugPrint(
                '[WS] Ride offer was not receipted in time; not surfacing');
            return;
          }
          final actionable = received.payload;
          final ride = Ride.fromJson(actionable);
          final expiresAt = received.decisionExpiresAt;
          ref.container.read(rideOfferIdByRideProvider.notifier).update(
                (offers) => {...offers, ride.id: received.offerId},
              );
          ref.container.read(rideRequestDeadlineByIdProvider.notifier).update(
                (m) => {...m, ride.id: expiresAt},
              );

          // Drop re-broadcasts for a ride we've already accepted. The backend
          // re-fires `ride:request` / `ride:new` to all notified drivers until
          // one acks; once we've accepted, those re-fires would otherwise pop
          // the request screen back over the active-ride screen.
          final active = ref.container.read(activeRideProvider).ride;
          if (active != null && active.id == ride.id) {
            debugPrint('[WS] Skipping re-broadcast for active ride ${ride.id}');
            return;
          }

          // Dedupe pre-acceptance re-fires (the legacy `ride:request` fires
          // alongside the new `ride:new`, and the matcher re-emits to the same
          // driver every few seconds until they ack). Once we've surfaced the
          // request screen for this ride id, subsequent emits should not push
          // a new screen on top.
          final surfaced = ref.container.read(surfacedRideIdsProvider);
          if (surfaced.contains(ride.id)) {
            // FCM can win the receipt race with a privacy-minimised payload.
            // If the richer socket envelope follows, replace the in-memory
            // card without replaying sound/navigation so route coordinates
            // and stops are not left at fallback values.
            final current = ref.container.read(incomingRideRequestProvider);
            if (current?.id == ride.id) {
              ref.container.read(incomingRideRequestProvider.notifier).state =
                  ride;
              debugPrint('[WS] Enriched already-surfaced ride ${ride.id}');
            } else {
              debugPrint('[WS] Ride ${ride.id} already surfaced — skipping');
            }
            return;
          }
          ref.container.read(surfacedRideIdsProvider.notifier).update(
                (s) => {...s, ride.id},
              );

          ref.container.read(incomingRideRequestProvider.notifier).state = null;
          ref.container.read(incomingRideRequestProvider.notifier).state = ride;
          ref.container.read(navBadgeProvider.notifier).increment('/home');
        } catch (e) {
          debugPrint('[WS] Failed to parse ride: $e');
        }
      } else {
        debugPrint('[WS] Ride payload not a Map — got ${data.runtimeType}');
      }
    }

    void handleRide(dynamic data) {
      unawaited(receiveRide(data));
    }

    // off+on guards against duplicate handlers if _connectAndListen runs
    // more than once against the same socket instance.
    //
    // Backend stopped emitting `ride:request` per the architectural
    // migration; only `ride:new` carries new incoming requests now.
    socket
      ..off('ride:new')
      ..on('ride:new', handleRide);

    // Another driver accepted this offer, or the matcher/cancellation flow
    // explicitly revoked it. Clear every pre-acceptance surface immediately;
    // waiting for the local countdown leaves a stale screen ringing after the
    // backend has already moved on.
    void handleRideDismissed(dynamic data) {
      if (data is! Map) return;
      final rideId = data['rideId']?.toString() ?? data['id']?.toString();
      if (rideId == null || rideId.isEmpty) return;
      final reason = data['reason']?.toString() ?? 'revoked';
      ref.container.read(rideOfferDismissalProvider.notifier).state =
          RideOfferDismissal(rideId: rideId, reason: reason);
      final current = ref.container.read(incomingRideRequestProvider);
      if (current?.id == rideId) {
        ref.container.read(incomingRideRequestProvider.notifier).state = null;
      }
      ref.container.read(rideRequestDeadlineByIdProvider.notifier).update(
            (deadlines) => {...deadlines}..remove(rideId),
          );
      final offerId = ref.container.read(rideOfferIdByRideProvider)[rideId];
      ref.container.read(rideOfferIdByRideProvider.notifier).update(
            (offers) => {...offers}..remove(rideId),
          );
      if (offerId != null) unawaited(clearStoredRideOffer(offerId));
      unawaited(
        clearIncomingRequestAlert(
          type: NotificationPayload.typeRideRequest,
          requestId: rideId,
          offerId: offerId,
        ),
      );
      if (isRiderCancellationRevocation(reason) &&
          claimRiderCancellationInAppNotice(rideId)) {
        final router = ref.container.read(goRouterProvider);
        final context = router.routerDelegate.navigatorKey.currentContext;
        if (context != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('The rider cancelled this ride request.'),
                duration: Duration(seconds: 5),
              ),
            );
        }
      }
    }

    socket
      ..off('ride:dismissed')
      ..on('ride:dismissed', handleRideDismissed);

    // Listen for incoming job requests (artisan) — new + legacy event names
    void handleJob(dynamic data) {
      // Never print the full request: it can contain the customer's name,
      // exact address, description and photo URLs. Keep only routing metadata
      // in release/device logs.
      if (data is Map) {
        debugPrint(
          '[WS] Received job event id=${data['id'] ?? data['jobId']} '
          'keys=${data.keys.join(',')}',
        );
      } else {
        debugPrint('[WS] Received job event type=${data.runtimeType}');
      }
      if (data is Map<String, dynamic>) {
        try {
          final job = Job.fromJson(data);
          // Dedupe against the poller — if the REST fallback already
          // surfaced this job, skip the duplicate modal.
          final surfaced = ref.container.read(surfacedJobIdsProvider);
          if (surfaced.contains(job.id)) {
            debugPrint('[WS] Job ${job.id} already surfaced — skipping');
            return;
          }
          ref.container.read(surfacedJobIdsProvider.notifier).update(
                (s) => {...s, job.id},
              );
          // Force a state transition even if an identical Job instance is
          // somehow already in the provider (defensive — Job doesn't
          // override ==, but the clear-then-set guarantees the listener
          // fires for every inbound event).
          ref.container.read(incomingJobRequestProvider.notifier).state = null;
          ref.container.read(incomingJobRequestProvider.notifier).state = job;
          ref.container.read(navBadgeProvider.notifier).increment('/home');
          debugPrint('[WS] Job ${job.id} pushed to incomingJobRequestProvider');
        } catch (e, st) {
          debugPrint('[WS] Failed to parse job: $e\n$st');
        }
      } else {
        debugPrint('[WS] Job payload not a Map — got ${data.runtimeType}');
      }
    }

    socket
      ..off('job:new')
      ..off('job:request')
      ..on('job:new', handleJob)
      ..on('job:request', handleJob); // legacy

    // Platform-wide anonymised "Live Job Feed" snapshots — independent of
    // category/radius eligibility. Drives the read-only artisan-home carousel.
    void handleJobFeed(dynamic data) {
      if (data is! Map<String, dynamic>) {
        debugPrint(
            '[WS] job:feed:new payload not a Map — got ${data.runtimeType}');
        return;
      }
      try {
        final snapshot = LiveFeedJob.fromJson(data);
        ref.container.read(liveJobFeedProvider.notifier).prepend(snapshot);
      } catch (e, st) {
        debugPrint('[WS] Failed to parse job:feed:new payload: $e\n$st');
      }
    }

    socket
      ..off('job:feed:new')
      ..on('job:feed:new', handleJobFeed);

    debugPrint('[WS] Job/ride listeners attached (id=${socket.isConnected})');

    // Canonical ride snapshot — fired by the backend on every ride state
    // change (status transition, fare update, location bump while active,
    // cancel, completion). Replaces the slim `ride:status` event. Payload
    // is the same shape as `GET /rides/:id`.
    void handleRideState(dynamic data) {
      if (data is! Map<String, dynamic>) return;
      try {
        final ride = Ride.fromJson(data);

        // Refresh every earnings surface + payouts when ANY ride completes
        // — backend's `recordRideCompletion()` writes a `Payment` row
        // fire-and-forget right after the status transition. The
        // invalidate is unconditional on `completed` (not gated on the
        // active-ride match) so a driver who has already navigated off
        // /active-ride still sees the dashboard refresh. Without that,
        // their earnings sat at the cached pre-trip value until they
        // pull-to-refreshed or cold-started.
        if (ride.status == RideStatus.completed) {
          try {
            ref.container.invalidate(todayCardProvider);
            ref.container.invalidate(earningsSummaryProvider);
            ref.container.invalidate(earningsReportProvider);
            ref.container.invalidate(payoutsProvider);
            ref.container.invalidate(driverTripsProvider);
          } catch (_) {/* providers may not be mounted in tests */}
        }

        // Only apply snapshots for the ride we're tracking. The driver
        // socket shouldn't see snapshots for unrelated rides, but guard
        // anyway in case the backend rooms ever cross-talk.
        final active = ref.container.read(activeRideProvider).ride;
        if (active != null && active.id != ride.id) return;
        ref.container.read(activeRideProvider.notifier).applySnapshot(ride);
      } catch (e) {
        debugPrint('[WS] Failed to apply ride:state snapshot: $e');
      }
    }

    socket
      ..off('ride:state')
      ..on('ride:state', handleRideState);

    // The canonical full snapshot is preferred, but cancellation also has a
    // slim dedicated event and a legacy status event. Listening to both keeps
    // the provider UI terminal even if snapshot generation fails or is late.
    void applyRideCancellation(dynamic data, {bool requireStatus = false}) {
      final rideId = rideCancellationIdFromEvent(
        data,
        requireCancelledStatus: requireStatus,
      );
      if (rideId == null) return;
      ref.container
          .read(activeRideProvider.notifier)
          .applyRemoteCancellation(rideId);
    }

    socket
      ..off('ride:cancelled')
      ..off('ride:status')
      ..on('ride:cancelled', (data) => applyRideCancellation(data))
      ..on(
        'ride:status',
        (data) => applyRideCancellation(data, requireStatus: true),
      );

    // Backend fires `ride:route_updated` when the rider adds or declines
    // a stop. The event itself only carries a thin `{rideId, …}` shape,
    // not the new stops list, so we re-fetch the full ride via REST and
    // hand it to applySnapshot — which now preserves the stops list
    // through subsequent stops-less `ride:state` snapshots.
    void handleRouteUpdated(dynamic data) {
      String? rideId;
      if (data is Map<String, dynamic>) {
        rideId = data['rideId'] as String? ?? data['id'] as String?;
      }
      rideId ??= ref.container.read(activeRideProvider).ride?.id;
      if (rideId == null) return;
      final svc = ref.container.read(rideServiceProvider);
      svc.getRide(rideId).then((json) {
        try {
          final ride = Ride.fromJson(json);
          ref.container.read(activeRideProvider.notifier).applySnapshot(ride);
        } catch (e) {
          debugPrint('[WS] route_updated parse failed: $e');
        }
      }).catchError((Object e) {
        debugPrint('[WS] route_updated refetch failed: $e');
      });
    }

    socket
      ..off('ride:route_updated')
      ..on('ride:route_updated', handleRouteUpdated);

    // Listen for job status updates — emitted to the artisan's room when
    // their bid is accepted/rejected, when the job is cancelled, or when
    // it advances through the active-work phases. Refreshing the jobs
    // list re-fetches `myBid.status`, which the JobRequest banner reads.
    void handleJobStatus(dynamic data) {
      debugPrint('[WS] Received job:status');
      // Prefer silentReload over invalidate: invalidate tears down the
      // notifier and the constructor-triggered load() flips isLoading back
      // to true, which flashes the spinner on the My Jobs screen. A silent
      // reload swaps the data in place so the banner and list update live.
      try {
        if (ref.container.exists(artisanJobsProvider)) {
          ref.container.read(artisanJobsProvider.notifier).silentReload();
        }
      } catch (_) {}
      if (data is Map<String, dynamic>) {
        final jobId = data['jobId'] as String? ?? data['id'] as String?;
        if (jobId != null) {
          // Once a job moves past `open`, it can't be picked up from the
          // in-session "New" list any more — drop it so stale entries
          // don't linger after a decision has been made.
          ref.container
              .read(pendingIncomingJobsProvider.notifier)
              .remove(jobId);
          unawaited(
            clearIncomingRequestAlert(
              type: NotificationPayload.typeJobRequest,
              requestId: jobId,
            ),
          );
        }

        // If the event is for the currently-active job, push the new
        // status into activeJobProvider so the CompletionOverlay flips
        // through artisan_marked_complete → pending_payment → completed
        // without the artisan having to tap anything.
        final statusStr = data['status'] as String?;
        if (jobId != null && statusStr != null) {
          try {
            final active = ref.container.read(activeJobProvider);
            if (active.job?.id == jobId) {
              final nextStatus = JobStatus.fromString(statusStr);
              ref
                  .read(activeJobProvider.notifier)
                  .applyRemoteStatus(nextStatus);
            }
          } catch (_) {}
        }
      }
    }

    socket
      ..off('job:status')
      ..off('job:status:changed')
      ..off('job:bid_accepted')
      ..off('job:bid_rejected')
      ..off('bid:accepted')
      ..off('bid:rejected')
      ..off('job:cancelled')
      ..on('job:status', handleJobStatus)
      // Paystack flow uses the `:changed` suffix; older code emits plain
      // `job:status`. Listen for both so every status transition — including
      // pending_payment → completed — drives the artisan UI.
      ..on('job:status:changed', handleJobStatus)
      // Pragmatic fallbacks: if the backend names the bid-outcome event
      // something other than `job:status`, we still want the UI to react.
      ..on('job:bid_accepted', handleJobStatus)
      ..on('job:bid_rejected', handleJobStatus)
      ..on('bid:accepted', handleJobStatus)
      ..on('bid:rejected', handleJobStatus)
      // Client cancelled a job during the bidding window (pre-acceptance)
      // OR mid-trip. Same payload shape — `{jobId, status: 'cancelled', …}`
      // — so the existing handler does the right thing: drops the job
      // from the pending-incoming queue, marks the active job cancelled
      // if it was active. Without this listener the artisan kept seeing
      // bid requests for jobs the client had already pulled.
      ..on('job:cancelled', handleJobStatus);

    // Fired by the backend's POST /payments/acknowledge-cash when the
    // client lands on the payment screen and picks a method. Flips the
    // active job's clientPaymentAcknowledgedAt/clientPaymentMethod so the
    // CompletionOverlay's "Yes, I received payment" CTA enables.
    void handleClientPaymentAck(dynamic data) {
      debugPrint('[WS] Received job:client_payment_acknowledged');
      if (data is! Map<String, dynamic>) return;
      final jobId = data['jobId'] as String? ?? data['id'] as String?;
      final method = data['paymentMethod'] as String?;
      final ackAt = data['acknowledgedAt'] as String?;
      if (jobId == null || method == null || ackAt == null) return;
      try {
        ref.container.read(activeJobProvider.notifier).applyClientPaymentAck(
              jobId: jobId,
              paymentMethod: method,
              acknowledgedAt: ackAt,
            );
      } catch (_) {}
    }

    socket
      ..off('job:client_payment_acknowledged')
      ..on('job:client_payment_acknowledged', handleClientPaymentAck);

    // ── Rating prompt ────────────────────────────────────────────────────
    // Backend emits `rating:prompt` to the artisan/driver socket room when
    // a job/ride finalises. Foreground users would otherwise get nothing
    // until the FCM push fired (which doesn't arrive while the app is
    // open and connected). The active-screen completion listener still
    // handles the in-flow case; this handler is the safety net for users
    // who navigated away before completion landed.
    //
    // `ratingSheetShownFor` is captured from the outer provider scope so the
    // dedup set survives socket re-creations — without that, every
    // background→resume cycle would reset the set and pop a duplicate
    // sheet for any rating event the server re-delivers on reconnect.
    void handleRatingPrompt(dynamic data) {
      debugPrint('[WS] Received rating:prompt');
      if (data is! Map<String, dynamic>) return;
      final bookingType = data['bookingType'] as String?;
      final bookingId =
          (data['bookingId'] ?? data['rideId'] ?? data['jobId']) as String?;
      if (bookingType == null || bookingId == null || bookingId.isEmpty) {
        return;
      }
      // If the artisan is currently on /active-job (or the driver on
      // /active-ride), defer entirely — the screen's own status
      // listener will pop the sheet AND handle the post-rating
      // navigation to /earnings. Without this, both paths fired and
      // stacked two rating modals on top of each other.
      final router = ref.container.read(goRouterProvider);
      final currentPath = router.routerDelegate.currentConfiguration.uri.path;
      if (bookingType == 'artisan_job' || bookingType == 'job') {
        if (currentPath == '/active-job') return;
      } else if (bookingType == 'ride') {
        if (currentPath == '/active-ride') return;
      }
      // Per-process dedup — same emit reconnect-redelivered, or paired
      // with an FCM tap landing milliseconds later, must not stack a
      // second sheet on top.
      if (!ratingSheetShownFor.add(bookingId)) return;

      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null) return;

      // Hydrate the counter-party first name so the sheet reads
      // "Rate <name>" instead of the generic fallback. Mirror the
      // FCM-tap rating handler's hydration.
      Future<void> openSheet() async {
        if (bookingType == 'ride') {
          var firstName = 'Passenger';
          try {
            final raw = await ref.read(rideServiceProvider).getRide(bookingId);
            final ride = Ride.fromJson(raw);
            final name = ride.clientName;
            if (name != null && name.trim().isNotEmpty) {
              firstName = name.trim().split(RegExp(r'\s+')).first;
            }
          } catch (e) {
            debugPrint('[WS] hydrate ride for rating failed: $e');
          }
          if (!ctx.mounted) return;
          await showRatePassengerSheet(
            ctx,
            rideId: bookingId,
            passengerFirstName: firstName,
          );
        } else if (bookingType == 'artisan_job' || bookingType == 'job') {
          var firstName = 'Client';
          try {
            final raw =
                await ref.container.read(jobServiceProvider).getJob(bookingId);
            final job = Job.fromJson(raw);
            final name = job.clientName;
            if (name != null && name.trim().isNotEmpty) {
              firstName = name.trim().split(RegExp(r'\s+')).first;
            }
          } catch (e) {
            debugPrint('[WS] hydrate job for rating failed: $e');
          }
          if (!ctx.mounted) return;
          await showRateClientSheet(
            ctx,
            jobId: bookingId,
            clientFirstName: firstName,
          );
        } else {
          // Unknown bookingType — release the dedup so a corrected
          // re-emit can still surface.
          ratingSheetShownFor.remove(bookingId);
        }
      }

      unawaited(openSheet());
    }

    socket
      ..off('rating:prompt')
      ..on('rating:prompt', handleRatingPrompt);
  }

  // Wire the post-create hook BEFORE kicking off the first connect so
  // the very first io.Socket also gets handlers attached. The hook
  // fires synchronously inside `SocketService.connect()` right after
  // the io.Socket is constructed, which is well before the server
  // emits any room-targeted events to the freshly-joined client.
  socket.onAfterCreate(attachHandlers);
  socket.connect();
}
