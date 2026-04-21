import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../features/auth/providers/current_user_provider.dart';
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
/// The backend matcher requires `current_location IS NOT NULL`
/// AND `online_status = 'online'` — both are set server-side by the
/// `/location/{role}/update` endpoint.
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
      ref.read(lastSocketEventProvider.notifier).state =
          '$event: $trimmed';
    });


    // Listen for incoming ride requests (driver) — new + legacy event names.
    // Minimal handler — kept simple on purpose. The payload extractor is
    // defined below (shared with the job handlers).
    void handleRide(dynamic data) {
      debugPrint('[WS] handleRide invoked, data type=${data.runtimeType}');
      Map<String, dynamic>? payload;
      if (data is Map<String, dynamic>) {
        payload = data;
      } else if (data is List && data.isNotEmpty && data.first is Map) {
        payload = Map<String, dynamic>.from(data.first as Map);
      } else if (data is Map) {
        payload = Map<String, dynamic>.from(data);
      }
      if (payload == null) {
        debugPrint('[WS] Could not extract ride payload — data=$data');
        return;
      }
      try {
        final ride = Ride.fromJson(payload);
        debugPrint('[WS] Parsed ride id=${ride.id} — pushing to provider');
        ref.read(incomingRideRequestProvider.notifier).state = ride;
        ref.read(navBadgeProvider.notifier).increment('/home');
      } catch (e) {
        debugPrint('[WS] Failed to parse ride: $e');
        debugPrint('[WS] Ride payload was: $payload');
      }
    }

    socket
      ..on('ride:new', handleRide)
      ..on('ride:request', handleRide); // legacy

    // Extract the event payload — Socket.IO may deliver it as a Map or a
    // single-element List (gateway config dependent). Shared by both
    // handlers below.
    Map<String, dynamic>? extractPayload(dynamic data) {
      if (data is Map<String, dynamic>) return data;
      if (data is List && data.isNotEmpty && data.first is Map) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    }

    // ── Standard job:new flow ──
    // Minimal handler — parse + push. No dedupe, no filtering. This MUST
    // stay simple so it can't be accidentally broken by admin-flow logic.
    void handleJobNew(dynamic data) {
      debugPrint('[WS] handleJobNew invoked, data type=${data.runtimeType}');
      final payload = extractPayload(data);
      if (payload == null) {
        debugPrint('[WS] job:new payload extraction failed — data=$data');
        return;
      }
      try {
        final job = Job.fromJson(payload);
        debugPrint('[WS] Parsed job:new id=${job.id} — pushing to provider');
        ref.read(incomingJobRequestProvider.notifier).state = job;
        ref.read(navBadgeProvider.notifier).increment('/home');
      } catch (e) {
        debugPrint('[WS] Failed to parse job:new: $e');
        debugPrint('[WS] Payload was: $payload');
      }
    }

    socket
      ..on('job:new', handleJobNew)
      ..on('job:request', handleJobNew); // legacy

    // ── Admin-assigned flow (separate handler) ──
    // Admin routes can fire duplicates (two rooms) and can land on
    // artisans who weren't picked, so we dedupe + filter here. Entirely
    // self-contained — nothing in this block can affect job:new.
    String? lastAdminKey;
    DateTime? lastAdminAt;
    const adminDedupeWindow = Duration(seconds: 3);

    void handleJobAdminAssigned(dynamic data) {
      debugPrint('[WS] handleJobAdminAssigned invoked');
      final payload = extractPayload(data);
      if (payload == null) {
        debugPrint('[WS] job:admin_assigned payload extraction failed');
        return;
      }
      try {
        final job = Job.fromJson(payload);

        // Only show it if THIS artisan is the one the admin picked.
        final me = ref.read(currentUserProvider);
        if (job.assignedArtisanId != null &&
            me != null &&
            job.assignedArtisanId != me.id) {
          debugPrint(
            '[WS] admin_assigned not for me (assigned=${job.assignedArtisanId}, '
            'me=${me.id}) — ignoring',
          );
          return;
        }

        // Dedupe the double delivery from dual-room emission.
        final key = job.id;
        final now = DateTime.now();
        if (lastAdminKey == key &&
            lastAdminAt != null &&
            now.difference(lastAdminAt!) < adminDedupeWindow) {
          debugPrint('[WS] admin_assigned duplicate — skipping');
          return;
        }
        lastAdminKey = key;
        lastAdminAt = now;

        debugPrint('[WS] Parsed admin_assigned id=${job.id} — pushing');
        ref.read(incomingJobRequestProvider.notifier).state = job;
        ref.read(navBadgeProvider.notifier).increment('/home');
      } catch (e) {
        debugPrint('[WS] Failed to parse job:admin_assigned: $e');
        debugPrint('[WS] Payload was: $payload');
      }
    }

    socket.on('job:admin_assigned', handleJobAdminAssigned);

    // Listen for ride status updates
    socket.on('ride:status', (data) {
      debugPrint('[WS] Received ride:status: $data');
    });

    // Listen for job status updates — backend fires this when a job moves
    // between states (e.g. admin_assigned → confirmed after the assigned
    // artisan submits their quote).
    void handleJobStatus(dynamic data) {
      debugPrint('[WS] Received job:status event: $data');
      // Tell the jobs list to refresh so the card re-renders with the new
      // status / agreedPricePesewas. Best-effort — safe even if the list
      // isn't currently being watched.
      try {
        ref.invalidate(artisanJobsProvider);
      } catch (_) {}
    }

    socket
      ..on('job:status', handleJobStatus)
      ..on('job:status:changed', handleJobStatus);
  });
}
