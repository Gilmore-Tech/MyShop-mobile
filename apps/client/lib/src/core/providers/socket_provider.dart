import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' show RideStop;

import '../../features/auth/providers/auth_controller.dart';
import '../../features/activity/providers/activity_history_provider.dart';
import '../../features/activity/providers/activity_provider.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/ride/providers/edit_trip_provider.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../../features/services/providers/active_job_provider.dart';
import '../../features/services/providers/bid_detail_provider.dart';
import '../../features/services/providers/bid_list_provider.dart';
import '../../features/services/providers/job_detail_provider.dart';
import '../di/providers.dart';
import 'nav_badge_provider.dart';

/// True while the Socket.IO connection is open. Mirrored from the underlying
/// [SocketService.connectionStream] inside [_connectAndListen] so other
/// providers can react to connect/reconnect transitions (e.g. the
/// active-ride recovery bridge re-checks for a stranded ride when the
/// socket finally comes through after a Render cold-start).
final socketConnectedProvider = StateProvider<bool>((_) => false);

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
  // `ride:state` snapshots. Without this, an emit issued before the
  // handshake completes is dropped silently and the rider is stuck on the
  // matching screen indefinitely.
  socket.connectionStream.listen((connected) {
    ref.read(socketConnectedProvider.notifier).state = connected;
    if (!connected) return;
    final rideId = ref.read(activeRideIdProvider);
    if (rideId == null || rideId.isEmpty) return;
    developer.log('Socket connected — joining ride room $rideId', name: 'WS');
    socket.emit('client:track:ride', {'rideId': rideId});
  });

  socket.connect().then((_) {
    // Diagnostic: log every event the rider's socket sees so we can tell
    // a "no events arriving" problem (room-join race, auth issue) apart
    // from a "wrong event name" problem (backend renamed something) at a
    // glance. Stripped to the first ~200 chars to keep the log readable.
    socket.onAnyEvent((event, data) {
      final preview = data.toString();
      final trimmed =
          preview.length > 200 ? '${preview.substring(0, 200)}…' : preview;
      developer.log('[any] $event → $trimmed', name: 'WS');
    });

    // Apply a `ride:state` snapshot — the backend's canonical event that
    // fires on every ride state change (status transition, fare update,
    // location bump while active, cancel, completion). Drives every ride
    // provider on the rider side: matched driver, booking phase, tracking
    // phase, and the live driver marker.
    //
    // Replaces the legacy `ride:accepted` + `ride:status` listeners and
    // the multi-name `ride:driver_location` / `ride:location` guesses;
    // backend's M-1 spec guarantees one event with a full snapshot.
    void applyRideSnapshot(Map<String, dynamic> data) {
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

      // Drive the booking + tracking phases off the ride status. The
      // matching screen listens for `bookingPhase == accepted` to navigate;
      // the tracking screen listens for `rideTrackingPhase` transitions to
      // drive timers and the eventual `/ride-complete` redirect.
      final status = data['status'] as String? ?? '';
      switch (status) {
        case 'accepted' ||
              'driver_assigned' ||
              'driver_en_route' ||
              'arrived_at_pickup' ||
              'arrived' ||
              'in_progress':
          // Only push the matched-driver model once the driver is real
          // (avoid clobbering with a half-built model on `requested`).
          ref.read(matchedDriverProvider.notifier).state = matched;
          ref.read(bookingPhaseProvider.notifier).accepted();
          ref.read(rideMatchedViaSocketProvider.notifier).state = true;
        case 'completed':
          // Final snapshot — keep the matched driver around for the
          // receipt screen but flip tracking phase to navigate away.
          ref.read(matchedDriverProvider.notifier).state = matched;
        case 'cancelled' || 'no_drivers':
          // Failed states: clear out so the matching screen can render
          // its failure card and the activity list refreshes.
          break;
        default:
          break;
      }

      // Tracking phase (only when the ride is past `accepted`).
      switch (status) {
        case 'driver_en_route':
          ref.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.enRoute;
        case 'arrived_at_pickup' || 'arrived':
          ref.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.arrived;
        case 'in_progress':
          ref.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.inProgress;
        case 'completed':
          ref.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.completed;
          // Build the receipt from the same snapshot before the tracking
          // screen navigates to /ride-complete — without this the rider
          // lands on the receipt screen with a null provider and an
          // empty fallback.
          ref.read(rideReceiptProvider.notifier).state =
              buildRideReceiptFromSnapshot(data);
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

      // Snapshot may also carry the driver's last fix as a field on the
      // driver sub-object — seed the live position provider so the map's
      // marker has something to render before the next per-fix
      // `driver:location` event arrives.
      //
      // Backend's RideSnapshot uses `currentLat` / `currentLng` (see
      // `apps/api/src/modules/ride/ride-snapshot.service.ts`); we keep
      // `latitude` / `lat` aliases as defensive fallbacks in case other
      // emit sites use the per-fix payload shape.
      final dLat =
          (driver['currentLat'] ?? driver['latitude'] ?? driver['lat']) as num?;
      final dLng = (driver['currentLng'] ??
          driver['longitude'] ??
          driver['lng']) as num?;
      if (dLat != null && dLng != null) {
        final heading = (driver['heading'] ?? driver['bearing']) as num?;
        ref.read(liveDriverPositionProvider.notifier).state =
            LiveDriverPosition(
          latitude: dLat.toDouble(),
          longitude: dLng.toDouble(),
          heading: heading?.toDouble(),
          updatedAt: DateTime.now(),
        );
      }
    }

    socket
      ..off('ride:state')
      ..on('ride:state', (data) {
        if (data is! Map<String, dynamic>) return;
        try {
          applyRideSnapshot(data);
        } catch (e) {
          developer.log('Failed to apply ride:state snapshot: $e',
              name: 'WS', level: 900);
        }
      });

    // ── Route changes (rider added / cancelled a stop) ──────────────────
    // Backend emits `ride:route_updated` to the room when stops change.
    // The event payload doesn't carry the new stops list, so we re-fetch
    // the full ride and re-seed `tripStopsProvider` — the AddStopScreen
    // (and any future "stops list" widget) renders from there.
    socket
      ..off('ride:route_updated')
      ..on('ride:route_updated', (data) {
        final rideId = ref.read(activeRideIdProvider);
        if (rideId == null || rideId.isEmpty) return;
        ref.read(rideServiceProvider).getRide(rideId).then((json) {
          try {
            final stops = (json['stops'] as List<dynamic>?)
                    ?.whereType<Map<String, dynamic>>()
                    .map(RideStop.fromJson)
                    .toList() ??
                const <RideStop>[];
            ref.read(tripStopsProvider.notifier).seed(
              pickup: (
                address: json['pickupAddress'] as String?,
                lat: (json['pickupLat'] as num?)?.toDouble(),
                lng: (json['pickupLng'] as num?)?.toDouble(),
              ),
              destination: (
                address: json['dropoffAddress'] as String?,
                lat: (json['dropoffLat'] as num?)?.toDouble(),
                lng: (json['dropoffLng'] as num?)?.toDouble(),
              ),
              existingStops: stops,
            );
          } catch (e) {
            developer.log('route_updated parse failed: $e',
                name: 'WS', level: 800);
          }
        }).catchError((Object e) {
          developer.log('route_updated refetch failed: $e',
              name: 'WS', level: 800);
        });
      });

    // ── Live driver location ─────────────────────────────────────────────
    // Per-fix marker updates. `ride:state` carries the full snapshot at a
    // ~5s cadence (throttled server-side); `driver:location` continues to
    // fire on every GPS bump so the marker animates smoothly between
    // snapshots. Gated on the active ride id so the rider's marker
    // doesn't jitter from unrelated ride traffic.
    void handleDriverLocation(dynamic data) {
      if (data is! Map<String, dynamic>) return;
      final activeRideId = ref.read(activeRideIdProvider);
      if (activeRideId == null) return;
      final eventRideId = data['rideId'] as String? ?? data['id'] as String?;
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
      ..off('driver:location')
      ..on('driver:location', handleDriverLocation);

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
