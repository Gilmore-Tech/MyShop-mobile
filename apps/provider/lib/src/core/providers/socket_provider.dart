import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/artisan_home/providers/active_job_provider.dart';
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/driver_earnings_provider.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../../features/trips/providers/driver_trips_provider.dart';
import 'availability_controller.dart';
import 'provider_status_provider.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import 'nav_badge_provider.dart';
import '../di/providers.dart';

/// Provides the [SocketService] singleton for the app.
final socketServiceProvider = Provider<SocketService>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final dio = ref.watch(dioProvider);
  final service = SocketService(
    config: config,
    tokenStorage: tokenStorage,
    dio: dio,
    onForceLogout: () {
      ref.read(authControllerProvider.notifier).logout();
    },
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

/// Incoming job request for artisans — populated by Socket.IO events.
final incomingJobRequestProvider = StateProvider<Job?>((ref) => null);

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

/// Pipes the location stream into both the socket AND the REST endpoint
/// so the backend can set `current_location` and `online_status = 'online'`.
///
/// Socket emit = real-time, low-latency feed for the matcher.
/// REST call   = durable write to the DB (throttled to avoid spamming).
///
/// Watched by the shell — activates whenever the provider is online.
final locationSocketBridgeProvider = Provider<void>((ref) {
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
  final locationService = ref.read(locationServiceProvider);
  final isArtisan = ref.read(providerTypeProvider).isArtisan;
  debugPrint('[LOC] bridge: active (role=${isArtisan ? 'artisan' : 'driver'})'
      ' — listening for fixes');

  Future<void> postLocation(Position position) async {
    try {
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
      debugPrint(
        '[LOC] REST updated ${isArtisan ? 'artisan' : 'driver'} '
        '(${position.latitude}, ${position.longitude})',
      );
    } catch (e) {
      debugPrint('[LOC] REST update failed: $e');
    }
  }

  // Heartbeat: backend's Redis driver entry has a 5-second TTL (EDD §5.3),
  // so we re-POST the last-known fix every 4s even when the phone is
  // stationary. Without this, a parked driver gets force-offlined within
  // ~5s of going online and stops receiving ride broadcasts.
  // Backend is rate-limited to 1 update per 3s; 4s sits comfortably above.
  //
  // The position-stream listener below is intentionally socket-only: doing
  // a REST POST on every fix (or even on the first fix per re-evaluation)
  // races the heartbeat and trips the 3s rate limit, which expires the
  // Redis entry and makes the driver invisible to the matcher.
  final heartbeat = Timer.periodic(const Duration(seconds: 4), (_) {
    final pos = ref.read(lastKnownPositionProvider);
    if (pos == null) return;
    socket.emit('driver:location:update', {
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'status': 'online',
    });
    postLocation(pos);
  });
  ref.onDispose(heartbeat.cancel);

  // Kick the heartbeat once immediately if we already have a cached fix —
  // otherwise the backend would wait up to 4s before seeing the driver,
  // and the rider's matcher could miss them on a freshly-online driver.
  // This is the only "first POST" we do; the position-stream listener
  // below intentionally does NOT post REST (heartbeat owns that channel).
  final cached = ref.read(lastKnownPositionProvider);
  if (cached != null) {
    socket.emit('driver:location:update', {
      'latitude': cached.latitude,
      'longitude': cached.longitude,
      'status': 'online',
    });
    postLocation(cached);
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
        ref.read(lastKnownPositionProvider.notifier).state = fresh;
        socket.emit('driver:location:update', {
          'latitude': fresh.latitude,
          'longitude': fresh.longitude,
          'status': 'online',
        });
        postLocation(fresh);
      } catch (e) {
        debugPrint('[LOC] bridge: cold-fix fetch failed: $e');
      }
    });
  }

  // Listen to the existing position stream so the cached fix advances as
  // the phone moves. Socket-only — the heartbeat is the single REST writer.
  ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
    next.when(
      data: (position) {
        ref.read(lastKnownPositionProvider.notifier).state = position;

        // Socket emit on every fix is cheap and gives the matcher fresh
        // coords between heartbeat ticks while the driver is moving.
        socket.emit('driver:location:update', {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'status': 'online',
        });
      },
      loading: () =>
          debugPrint('[LOC] bridge: stream loading — no fix yet'),
      error: (e, _) =>
          debugPrint('[LOC] bridge: stream error — $e'),
    );
  }, fireImmediately: true);
});

void _connectAndListen(Ref ref, SocketService socket) {
  // Track connection state so the UI can show an indicator.
  socket.connectionStream.listen((connected) {
    ref.read(socketConnectedProvider.notifier).state = connected;
  });

  socket.connect().then((_) {
    // Mirror every incoming event into a state provider for visual debugging.
    socket.onAnyEvent((event, data) {
      final preview = data.toString();
      final trimmed =
          preview.length > 200 ? '${preview.substring(0, 200)}…' : preview;
      ref.read(lastSocketEventProvider.notifier).state = '$event: $trimmed';
    });

    // Listen for incoming ride requests (driver) — new + legacy event names
    void handleRide(dynamic data) {
      debugPrint('[WS] Received ride event: $data');
      if (data is Map<String, dynamic>) {
        try {
          final ride = Ride.fromJson(data);

          // Drop re-broadcasts for a ride we've already accepted. The backend
          // re-fires `ride:request` / `ride:new` to all notified drivers until
          // one acks; once we've accepted, those re-fires would otherwise pop
          // the request screen back over the active-ride screen.
          final active = ref.read(activeRideProvider).ride;
          if (active != null && active.id == ride.id) {
            debugPrint('[WS] Skipping re-broadcast for active ride ${ride.id}');
            return;
          }

          // Dedupe pre-acceptance re-fires (the legacy `ride:request` fires
          // alongside the new `ride:new`, and the matcher re-emits to the same
          // driver every few seconds until they ack). Once we've surfaced the
          // request screen for this ride id, subsequent emits should not push
          // a new screen on top.
          final surfaced = ref.read(surfacedRideIdsProvider);
          if (surfaced.contains(ride.id)) {
            debugPrint('[WS] Ride ${ride.id} already surfaced — skipping');
            return;
          }
          ref.read(surfacedRideIdsProvider.notifier).update(
                (s) => {...s, ride.id},
              );

          ref.read(incomingRideRequestProvider.notifier).state = null;
          ref.read(incomingRideRequestProvider.notifier).state = ride;
          ref.read(navBadgeProvider.notifier).increment('/home');
        } catch (e) {
          debugPrint('[WS] Failed to parse ride: $e');
        }
      } else {
        debugPrint('[WS] Ride payload not a Map — got ${data.runtimeType}');
      }
    }

    // off+on guards against duplicate handlers if _connectAndListen runs
    // more than once against the same socket instance.
    //
    // Backend stopped emitting `ride:request` per the architectural
    // migration; only `ride:new` carries new incoming requests now.
    socket
      ..off('ride:new')
      ..on('ride:new', handleRide);

    // Listen for incoming job requests (artisan) — new + legacy event names
    void handleJob(dynamic data) {
      debugPrint('[WS] Received job event: $data');
      if (data is Map<String, dynamic>) {
        try {
          final job = Job.fromJson(data);
          // Dedupe against the poller — if the REST fallback already
          // surfaced this job, skip the duplicate modal.
          final surfaced = ref.read(surfacedJobIdsProvider);
          if (surfaced.contains(job.id)) {
            debugPrint('[WS] Job ${job.id} already surfaced — skipping');
            return;
          }
          ref.read(surfacedJobIdsProvider.notifier).update(
                (s) => {...s, job.id},
              );
          // Force a state transition even if an identical Job instance is
          // somehow already in the provider (defensive — Job doesn't
          // override ==, but the clear-then-set guarantees the listener
          // fires for every inbound event).
          ref.read(incomingJobRequestProvider.notifier).state = null;
          ref.read(incomingJobRequestProvider.notifier).state = job;
          ref.read(navBadgeProvider.notifier).increment('/home');
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

    debugPrint('[WS] Job/ride listeners attached (id=${socket.isConnected})');

    // Canonical ride snapshot — fired by the backend on every ride state
    // change (status transition, fare update, location bump while active,
    // cancel, completion). Replaces the slim `ride:status` event. Payload
    // is the same shape as `GET /rides/:id`.
    void handleRideState(dynamic data) {
      if (data is! Map<String, dynamic>) return;
      try {
        final ride = Ride.fromJson(data);
        final active = ref.read(activeRideProvider).ride;
        // Only apply snapshots for the ride we're tracking. The driver
        // socket shouldn't see snapshots for unrelated rides, but guard
        // anyway in case the backend rooms ever cross-talk.
        if (active != null && active.id != ride.id) return;
        ref.read(activeRideProvider.notifier).applySnapshot(ride);

        // Refresh earnings + payouts when the ride completes — the
        // backend's `recordRideCompletion()` writes a `Payment` row
        // fire-and-forget right after the status transition, so the new
        // /payments/earnings totals land within a tick or two of this
        // snapshot. Invalidating both providers means the dashboard
        // (and the home-screen earnings card) reflect the new trip
        // without the driver pulling-to-refresh.
        if (ride.status == RideStatus.completed) {
          try {
            ref.invalidate(driverEarningsProvider);
            ref.invalidate(driverPayoutsProvider);
            ref.invalidate(driverTripsProvider);
          } catch (_) {/* providers may not be mounted in tests */}
        }
      } catch (e) {
        debugPrint('[WS] Failed to apply ride:state snapshot: $e');
      }
    }

    socket
      ..off('ride:state')
      ..on('ride:state', handleRideState);

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
      rideId ??= ref.read(activeRideProvider).ride?.id;
      if (rideId == null) return;
      final svc = ref.read(rideServiceProvider);
      svc.getRide(rideId).then((json) {
        try {
          final ride = Ride.fromJson(json);
          ref.read(activeRideProvider.notifier).applySnapshot(ride);
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
      debugPrint('[WS] Received job:status: $data');
      // Prefer silentReload over invalidate: invalidate tears down the
      // notifier and the constructor-triggered load() flips isLoading back
      // to true, which flashes the spinner on the My Jobs screen. A silent
      // reload swaps the data in place so the banner and list update live.
      try {
        if (ref.exists(artisanJobsProvider)) {
          ref.read(artisanJobsProvider.notifier).silentReload();
        }
      } catch (_) {}
      if (data is Map<String, dynamic>) {
        final jobId =
            data['jobId'] as String? ?? data['id'] as String?;
        if (jobId != null) {
          // Once a job moves past `open`, it can't be picked up from the
          // in-session "New" list any more — drop it so stale entries
          // don't linger after a decision has been made.
          ref.read(pendingIncomingJobsProvider.notifier).remove(jobId);
        }

        // If the event is for the currently-active job, push the new
        // status into activeJobProvider so the CompletionOverlay flips
        // through artisan_marked_complete → pending_payment → completed
        // without the artisan having to tap anything.
        final statusStr = data['status'] as String?;
        if (jobId != null && statusStr != null) {
          try {
            final active = ref.read(activeJobProvider);
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
      ..on('bid:rejected', handleJobStatus);
  });
}
