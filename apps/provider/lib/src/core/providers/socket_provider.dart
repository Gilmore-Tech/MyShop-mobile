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
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
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
/// Automatically connects when the provider goes online and disconnects
/// when they go offline. Listens for incoming ride/job events and pushes
/// them into the appropriate state providers.
final socketConnectionProvider = Provider<void>((ref) {
  final status = ref.watch(providerStatusProvider);
  final socket = ref.read(socketServiceProvider);

  if (status.isOnline) {
    _connectAndListen(ref, socket);
  } else {
    socket.disconnect();
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
  if (!status.isOnline) {
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
    socket.emit('location:update', {
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
    socket.emit('location:update', {
      'latitude': cached.latitude,
      'longitude': cached.longitude,
      'status': 'online',
    });
    postLocation(cached);
  }

  // Listen to the existing position stream so the cached fix advances as
  // the phone moves. Socket-only — the heartbeat is the single REST writer.
  ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
    next.when(
      data: (position) {
        ref.read(lastKnownPositionProvider.notifier).state = position;

        // Socket emit on every fix is cheap and gives the matcher fresh
        // coords between heartbeat ticks while the driver is moving.
        socket.emit('location:update', {
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
    socket
      ..off('ride:new')
      ..off('ride:request')
      ..on('ride:new', handleRide)
      ..on('ride:request', handleRide); // legacy

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

    // Listen for ride status updates — pushed when the client cancels, when
    // the matcher reassigns a ride that's been ignored, or when the backend
    // echoes a status the driver just set. Mirrors the artisan job:status
    // handler so the active-ride sheet stays in sync without polling.
    void handleRideStatus(dynamic data) {
      debugPrint('[WS] Received ride:status: $data');
      if (data is! Map<String, dynamic>) return;
      final rideId = data['rideId'] as String? ?? data['id'] as String?;
      final statusStr = data['status'] as String?;
      if (rideId == null || statusStr == null) return;
      try {
        final active = ref.read(activeRideProvider).ride;
        if (active?.id != rideId) return;
        final next = RideStatus.fromString(statusStr);
        ref.read(activeRideProvider.notifier).applyRemoteStatus(next);
      } catch (_) {}
    }

    socket
      ..off('ride:status')
      ..on('ride:status', handleRideStatus);

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
