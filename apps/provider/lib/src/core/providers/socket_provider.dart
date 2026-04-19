import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/driver_home/providers/driver_status_provider.dart';
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

/// Pipes the location stream into the socket so the backend can set
/// `current_location` and match jobs/rides within the provider's radius.
///
/// Watched by the shell — activates whenever the provider is online.
final locationSocketBridgeProvider = Provider<void>((ref) {
  final status = ref.watch(driverStatusProvider);
  if (!status.isOnline) return;

  final connected = ref.watch(socketConnectedProvider);
  if (!connected) return;

  final socket = ref.read(socketServiceProvider);

  // Listen to the existing position stream and emit `location:update`
  // to the backend whenever a new fix arrives.
  ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
    next.whenData((position) {
      socket.emit('location:update', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'status': 'online',
      });
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


    // Listen for incoming ride requests (driver) — new + legacy event names
    void handleRide(dynamic data) {
      debugPrint('[WS] Received ride event');
      if (data is Map<String, dynamic>) {
        try {
          final ride = Ride.fromJson(data);
          ref.read(incomingRideRequestProvider.notifier).state = ride;
          ref.read(navBadgeProvider.notifier).increment('/home');
        } catch (e) {
          debugPrint('[WS] Failed to parse ride: $e');
        }
      }
    }

    socket
      ..on('ride:new', handleRide)
      ..on('ride:request', handleRide); // legacy

    // Listen for incoming job requests (artisan) — new + legacy event names
    void handleJob(dynamic data) {
      debugPrint('[WS] Received job event');
      if (data is Map<String, dynamic>) {
        try {
          final job = Job.fromJson(data);
          ref.read(incomingJobRequestProvider.notifier).state = job;
          ref.read(navBadgeProvider.notifier).increment('/home');
        } catch (e) {
          debugPrint('[WS] Failed to parse job: $e');
        }
      }
    }

    socket
      ..on('job:new', handleJob)
      ..on('job:request', handleJob); // legacy

    // Listen for ride status updates
    socket.on('ride:status', (data) {
      debugPrint('[WS] Received ride:status: $data');
    });

    // Listen for job status updates
    socket.on('job:status', (data) {
      debugPrint('[WS] Received job:status: $data');
    });
  });
}
