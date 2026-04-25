import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/activity/providers/activity_history_provider.dart';
import '../../features/activity/providers/activity_provider.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../../features/services/providers/active_job_provider.dart';
import '../../features/services/providers/bid_detail_provider.dart';
import '../../features/services/providers/bid_list_provider.dart';
import '../../features/services/providers/job_detail_provider.dart';
import '../di/providers.dart';
import 'nav_badge_provider.dart';

/// Provides the [SocketService] singleton for the client app.
final socketServiceProvider = Provider<SocketService>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final dio = ref.watch(dioProvider);
  final service = SocketService(
    config: config,
    tokenStorage: tokenStorage,
    dio: dio,
    onForceLogout: () {
      ref.read(clientAuthControllerProvider.notifier).logout();
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Manages the Socket.IO connection lifecycle for the client app.
///
/// Automatically connects when the user is authenticated and disconnects
/// when they log out. Listens for real-time events and pushes updates
/// into the appropriate state providers.
final socketConnectionProvider = Provider<void>((ref) {
  final authState = ref.watch(clientAuthControllerProvider);
  final socket = ref.read(socketServiceProvider);

  if (authState is AuthAuthenticated) {
    _connectAndListen(ref, socket);
  } else {
    socket.disconnect();
  }
});

void _connectAndListen(Ref ref, SocketService socket) {
  // Whenever the socket finishes connecting (initial or after a reconnect),
  // (re-)join the active ride's tracking room so the rider receives
  // `ride:accepted` / `ride:status` events. Without this, an emit issued
  // before the handshake completes is dropped silently and the rider is
  // stuck on the matching screen until the REST poll picks it up — which
  // also trips the backend rate limit on long searches.
  socket.connectionStream.listen((connected) {
    if (!connected) return;
    final rideId = ref.read(activeRideIdProvider);
    if (rideId == null || rideId.isEmpty) return;
    developer.log('Socket connected — joining ride room $rideId', name: 'WS');
    socket.emit('client:track:ride', {'rideId': rideId});
  });

  socket.connect().then((_) {
    // Build the matched-driver model from a payload that may come from
    // either `ride:status` (driver/fare fields at top level) or
    // `ride:accepted` (the backend's dedicated match event).
    void applyDriverMatch(Map<String, dynamic> data) {
      final driver =
          data['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};
      // Driver name may arrive as a single `name` field or split into
      // first/last; fall back gracefully so the rider doesn't see "Driver".
      final firstName = driver['firstName'] as String?;
      final lastName = driver['lastName'] as String?;
      final assembledName = (firstName != null || lastName != null)
          ? [firstName, lastName].whereType<String>().join(' ').trim()
          : null;
      final matched = MatchedDriver(
        name: (driver['name'] as String?) ??
            assembledName ??
            (driver['fullName'] as String?) ??
            'Driver',
        vehicle: driver['vehicle'] as String? ?? '',
        plateNumber: driver['plateNumber'] as String? ?? '',
        rating: (driver['rating'] as num?)?.toDouble() ?? 4.5,
        minutesAway: (driver['eta'] as num?)?.toInt() ?? 3,
        driversAvailable: 1,
        tripCount: (driver['tripCount'] as num?)?.toInt() ?? 0,
        isVerified: driver['isVerified'] as bool? ?? false,
        isPoliceChecked: driver['isPoliceChecked'] as bool? ?? false,
        maskedPhone: driver['maskedPhone'] as String? ?? '',
        vehicleTier: driver['vehicleTier'] as String? ?? '',
        baseFarePesewas: (data['baseFare'] as num?)?.toInt() ?? 0,
        distanceFarePesewas: (data['distanceFare'] as num?)?.toInt() ?? 0,
        distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
        bookingFeePesewas: (data['bookingFee'] as num?)?.toInt() ?? 0,
        vehicleShortName: driver['vehicleShortName'] as String? ?? '',
        confirmedFarePesewas: (data['totalFare'] as num?)?.toInt() ?? 0,
        paymentMethod: data['paymentMethod'] as String? ?? 'Cash',
        photoUrl: (driver['photoUrl'] as String?) ??
            (driver['profilePhotoUrl'] as String?) ??
            (driver['avatarUrl'] as String?) ??
            '',
      );
      ref.read(matchedDriverProvider.notifier).state = matched;
      ref.read(bookingPhaseProvider.notifier).accepted();
      ref.read(rideMatchedViaSocketProvider.notifier).state = true;
    }

    // The backend emits `ride:accepted` to the rider's tracking room as
    // soon as a driver wins the assignment race. Without this listener
    // the rider only learns about the match via the 2-second REST poll —
    // and if the poll's status field doesn't transition the rider stays
    // stuck on the matching screen indefinitely.
    socket.on('ride:accepted', (data) {
      developer.log('Received ride:accepted event: $data', name: 'WS');
      if (data is! Map<String, dynamic>) return;
      try {
        applyDriverMatch(data);
      } catch (e) {
        developer.log('Failed to handle ride:accepted: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Live driver location ─────────────────────────────────────────────
    // Backend relays the driver's `location:update` emits to the rider's
    // ride room while a ride is active. We don't have a single canonical
    // event name documented yet, so listen for the obvious variants and
    // gate on `rideId` matching the active ride. Anything that doesn't
    // match the active ride is ignored — keeps a chatty admin feed from
    // jumping the marker around if it ever leaks into this socket.
    void handleDriverLocation(dynamic data) {
      if (data is! Map<String, dynamic>) return;
      final activeRideId = ref.read(activeRideIdProvider);
      if (activeRideId == null) return;
      final eventRideId =
          data['rideId'] as String? ?? data['id'] as String?;
      if (eventRideId != null && eventRideId != activeRideId) return;
      final lat = (data['latitude'] ?? data['lat']) as num?;
      final lng = (data['longitude'] ?? data['lng']) as num?;
      if (lat == null || lng == null) return;
      final heading = (data['heading'] ?? data['bearing']) as num?;
      ref.read(liveDriverPositionProvider.notifier).state = LiveDriverPosition(
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        heading: heading?.toDouble(),
        updatedAt: DateTime.now(),
      );
    }

    socket
      ..off('ride:driver_location')
      ..off('driver:location')
      ..off('ride:location')
      ..on('ride:driver_location', handleDriverLocation)
      ..on('driver:location', handleDriverLocation)
      ..on('ride:location', handleDriverLocation);

    // ── Ride status updates ──────────────────────────────────────────────
    socket.on('ride:status', (data) {
      developer.log('Received ride:status event: $data', name: 'WS');
      if (data is! Map<String, dynamic>) return;
      try {
        final status = data['status'] as String? ?? '';

        switch (status) {
          case 'accepted' || 'driver_assigned':
            applyDriverMatch(data);

          case 'en_route':
            ref.read(rideTrackingPhaseProvider.notifier).state =
                RideTrackingPhase.enRoute;

          case 'arrived':
            ref.read(rideTrackingPhaseProvider.notifier).state =
                RideTrackingPhase.arrived;

          case 'in_progress':
            ref.read(rideTrackingPhaseProvider.notifier).state =
                RideTrackingPhase.inProgress;

          case 'completed':
            // Flip the tracking screen to its `completed` phase so it can
            // navigate to /ride-complete — the previous flow relied on
            // client-side timers to do this, which only worked when the
            // simulated trip ETA hit zero.
            ref.read(rideTrackingPhaseProvider.notifier).state =
                RideTrackingPhase.completed;
            // Ride completed — activity list should refresh
            if (ref.exists(activityNotifierProvider)) {
              ref.read(activityNotifierProvider.notifier).reload();
            }
            if (ref.exists(activityHistoryProvider)) {
              ref.read(activityHistoryProvider.notifier).silentReload();
            }
            ref.read(navBadgeProvider.notifier).increment('/activity');

          case 'cancelled' || 'no_drivers':
            ref.read(bookingPhaseProvider.notifier).reset();
            if (ref.exists(activityHistoryProvider)) {
              ref.read(activityHistoryProvider.notifier).silentReload();
            }
        }
      } catch (e) {
        developer.log('Failed to handle ride:status: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Job status updates ───────────────────────────────────────────────
    // The backend emits `job:status:changed` (new name per the Paystack
    // contract); older code emitted `job:status`. Listen to both so the
    // UI reacts whichever one the server uses.
    void handleJobStatus(dynamic data) {
      developer.log('Received job:status event', name: 'WS');
      try {
        // If the payload carries a jobId, refresh that job's detail + bids
        // + active-job cache so any currently-open detail/summary/payment
        // screen updates live (including pending_payment → completed).
        final jobId = data is Map<String, dynamic>
            ? (data['jobId'] as String? ?? data['id'] as String?)
            : null;
        if (jobId != null) {
          ref.invalidate(jobDetailProvider(jobId));
          ref.invalidate(bidsForJobProvider(jobId));
          ref.invalidate(activeJobProvider(jobId));
        }

        if (ref.exists(activityNotifierProvider)) {
          ref.read(activityNotifierProvider.notifier).reload();
        }
        if (ref.exists(activityHistoryProvider)) {
          ref.read(activityHistoryProvider.notifier).silentReload();
        }
        ref.read(navBadgeProvider.notifier).increment('/activity');
      } catch (e) {
        developer.log('Failed to handle job:status: $e',
            name: 'WS', level: 900);
      }
    }

    socket
      ..off('job:status')
      ..off('job:status:changed')
      ..on('job:status', handleJobStatus)
      ..on('job:status:changed', handleJobStatus);

    // ── Artisan confirmed a bid ──────────────────────────────────────────
    socket.on('job:artisan_confirmed', (data) {
      developer.log('Received job:artisan_confirmed event', name: 'WS');
      try {
        final etaLabel = data is Map<String, dynamic>
            ? data['etaLabel'] as String? ?? ''
            : '';
        if (ref.exists(bidDetailActionProvider)) {
          ref
              .read(bidDetailActionProvider.notifier)
              .onArtisanConfirmed(etaLabel: etaLabel);
        }
      } catch (e) {
        developer.log('Failed to handle job:artisan_confirmed: $e',
            name: 'WS', level: 900);
      }
    });

    // ── New bid on a job ─────────────────────────────────────────────────
    socket.on('job:bid_new', (data) {
      developer.log('Received job:bid_new event', name: 'WS');
      try {
        // Refresh the live job detail + bids list so the client sees the new
        // bid (and updated count) without having to pull-to-refresh.
        final jobId = data is Map<String, dynamic>
            ? (data['jobId'] as String? ?? data['id'] as String?)
            : null;
        if (jobId != null) {
          ref.invalidate(jobDetailProvider(jobId));
          ref.invalidate(bidsForJobProvider(jobId));
        }

        if (ref.exists(activityNotifierProvider)) {
          ref.read(activityNotifierProvider.notifier).reload();
        }
        ref.read(navBadgeProvider.notifier).increment('/activity');
      } catch (e) {
        developer.log('Failed to handle job:bid_new: $e',
            name: 'WS', level: 900);
      }
    });

    // ── New notification ─────────────────────────────────────────────────
    socket.on('notification:new', (data) {
      developer.log('Received notification:new event', name: 'WS');
      try {
        if (ref.exists(notifsProvider)) {
          ref.read(notifsProvider.notifier).reload();
        }
        ref.read(navBadgeProvider.notifier).increment('/profile');
      } catch (e) {
        developer.log('Failed to handle notification:new: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Profile updated ──────────────────────────────────────────────────
    socket.on('profile:updated', (data) {
      developer.log('Received profile:updated event', name: 'WS');
      try {
        ref.read(clientAuthControllerProvider.notifier).refreshProfile();
      } catch (e) {
        developer.log('Failed to handle profile:updated: $e',
            name: 'WS', level: 900);
      }
    });
  });
}
