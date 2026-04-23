import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/driver_home/providers/driver_status_provider.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import 'nav_badge_provider.dart';
import '../di/providers.dart';

/// Provides the [SocketService] singleton for the app.
final socketServiceProvider = Provider<SocketService>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final service = SocketService(
    config: config,
    tokenStorage: tokenStorage,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Incoming ride request for drivers — populated by Socket.IO events.
final incomingRideRequestProvider = StateProvider<Ride?>((ref) => null);

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
  final status = ref.watch(driverStatusProvider);
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
  final status = ref.watch(driverStatusProvider);
  if (!status.isOnline) return;

  final connected = ref.watch(socketConnectedProvider);
  if (!connected) return;

  final socket = ref.read(socketServiceProvider);
  final locationService = ref.read(locationServiceProvider);
  final isArtisan = ref.read(providerTypeProvider).isArtisan;

  DateTime? lastRestSentAt;
  const restThrottle = Duration(seconds: 15);

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

  // Listen to the existing position stream and emit `location:update`
  // to the backend whenever a new fix arrives.
  ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
    next.whenData((position) {
      // 1. Socket emit — fires on every GPS fix.
      socket.emit('location:update', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'status': 'online',
      });

      // 2. REST call — throttled; first fix always fires, then every 15s.
      final now = DateTime.now();
      final shouldPost = lastRestSentAt == null ||
          now.difference(lastRestSentAt!) >= restThrottle;
      if (shouldPost) {
        lastRestSentAt = now;
        postLocation(position);
      }
    });
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

    // Listen for ride status updates
    socket.off('ride:status');
    socket.on('ride:status', (data) {
      debugPrint('[WS] Received ride:status: $data');
    });

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
      }
    }

    socket
      ..off('job:status')
      ..off('job:bid_accepted')
      ..off('job:bid_rejected')
      ..off('bid:accepted')
      ..off('bid:rejected')
      ..on('job:status', handleJobStatus)
      // Pragmatic fallbacks: if the backend names the bid-outcome event
      // something other than `job:status`, we still want the UI to react.
      ..on('job:bid_accepted', handleJobStatus)
      ..on('job:bid_rejected', handleJobStatus)
      ..on('bid:accepted', handleJobStatus)
      ..on('bid:rejected', handleJobStatus);
  });
}
