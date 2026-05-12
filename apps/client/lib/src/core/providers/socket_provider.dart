import 'dart:async';
import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' show RideStop;

import '../../app/router.dart' show AppRoutes, routerProvider;
import '../../features/auth/providers/auth_controller.dart';
import '../../features/activity/providers/activity_history_provider.dart';
import '../../features/activity/providers/activity_provider.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/ride/providers/edit_trip_provider.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../../features/ride/widgets/rate_ride_sheet.dart';
import '../../features/services/providers/active_job_provider.dart';
import '../../features/services/providers/bid_detail_provider.dart';
import '../../features/services/providers/bid_list_provider.dart';
import '../../features/services/providers/job_detail_provider.dart';
import '../../features/services/widgets/rate_job_sheet.dart';
import '../di/providers.dart';
import 'nav_badge_provider.dart';

/// True while the Socket.IO connection is open. Mirrored from the underlying
/// [SocketService.connectionStream] inside [_connectAndListen] so other
/// providers can react to connect/reconnect transitions (e.g. the
/// active-ride recovery bridge re-checks for a stranded ride when the
/// socket finally comes through after a Render cold-start).
final socketConnectedProvider = StateProvider<bool>((_) => false);

/// Provides the [SocketService] singleton for the client app.
///
/// Refresh failures are handled by the shared [TokenRefresher]
/// (constructed inside `createDioClient`), which fires the
/// app-level `onForceLogout` set in [dioClientProvider] — that
/// dispatches through [forceLogoutHandlerProvider] to flip the
/// auth state, and the [logoutCleanupBridgeProvider] picks up
/// from there. The socket service itself no longer carries an
/// onForceLogout — kept consistent with the REST path.
final socketServiceProvider = Provider<SocketService>((ref) {
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
  // Reads inside socket listener closures go through `ref.container.read`
  // rather than `ref.read`. The socket outlives any single rebuild of
  // `socketConnectionProvider`, and an inbound event firing during the
  // transition window between dependency-change + rebuild trips Riverpod's
  // `_didChangeDependency` assertion (seen 11 May 2026 on driver accept).
  // Container reads sidestep that tracking. Keep `ref.onDispose`,
  // `ref.listen`, and `ref.watch` as-is — those belong to the synchronous
  // provider body.

  // Whenever the socket finishes connecting (initial or after a reconnect),
  // (re-)join the active ride's tracking room so the rider receives
  // `ride:state` snapshots. Without this, an emit issued before the
  // handshake completes is dropped silently and the rider is stuck on the
  // matching screen indefinitely.
  socket.connectionStream.listen((connected) {
    ref.container.read(socketConnectedProvider.notifier).state = connected;
    if (!connected) return;
    final rideId = ref.container.read(activeRideIdProvider);
    if (rideId != null && rideId.isNotEmpty) {
      developer.log('Socket connected — joining ride room $rideId', name: 'WS');
      socket.emit('client:track:ride', {'rideId': rideId});
    }
    // Re-join the job-tracking room on reconnect so the live artisan
    // marker keeps flowing without the screen having to re-mount. The
    // tracking screen sets `trackedJobIdProvider` on init and clears
    // it on dispose; this listener mirrors the rider re-track flow.
    final jobId = ref.container.read(trackedJobIdProvider);
    if (jobId != null && jobId.isNotEmpty) {
      developer.log('Socket connected — joining job room $jobId', name: 'WS');
      socket.emit('client:track:job', {'jobId': jobId});
    }
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
        rating: (driver['rating'] as num?)?.toDouble(),
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
          ref.container.read(matchedDriverProvider.notifier).state = matched;
          ref.container.read(bookingPhaseProvider.notifier).accepted();
          ref.container.read(rideMatchedViaSocketProvider.notifier).state = true;
        case 'completed':
          // Final snapshot — keep the matched driver around for the
          // receipt screen but flip tracking phase to navigate away.
          ref.container.read(matchedDriverProvider.notifier).state = matched;
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
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.enRoute;
        case 'arrived_at_pickup' || 'arrived':
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.arrived;
        case 'in_progress':
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.inProgress;
        case 'completed':
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.completed;
          // Build the receipt from the same snapshot before the tracking
          // screen navigates to /ride-complete — without this the rider
          // lands on the receipt screen with a null provider and an
          // empty fallback.
          ref.container.read(rideReceiptProvider.notifier).state =
              buildRideReceiptFromSnapshot(data);
          if (ref.container.exists(activityNotifierProvider)) {
            ref.container.read(activityNotifierProvider.notifier).reload();
          }
          if (ref.container.exists(activityHistoryProvider)) {
            ref.container.read(activityHistoryProvider.notifier).silentReload();
          }
          ref.container.read(navBadgeProvider.notifier).increment('/activity');
        case 'cancelled' || 'no_drivers':
          // Flip to `failed` (not `idle`) so the matching screen renders
          // the failure card. Previously `reset()` sent the rider back to
          // an empty idle state and they were stranded on the spinner.
          final reason = (data['cancellationReason'] as String?) ?? '';
          final cancelledBy = (data['cancelledBy'] as String?) ?? '';
          final isNoDrivers = status == 'no_drivers' ||
              reason == 'no_drivers_available' ||
              cancelledBy == 'system';
          final friendlyMessage = isNoDrivers
              ? "We couldn't find a driver nearby. Please try again in a moment."
              : (reason.isNotEmpty ? reason : 'This ride was cancelled.');
          ref.container.read(bookingFailureMessageProvider.notifier).state =
              friendlyMessage;
          ref.container.read(bookingPhaseProvider.notifier).fail();
          if (ref.container.exists(activityHistoryProvider)) {
            ref.container.read(activityHistoryProvider.notifier).silentReload();
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
        ref.container.read(liveDriverPositionProvider.notifier).state =
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

    // Backend pushes `ride:matcher_progress` on every dispatch attempt —
    // initial broadcast, decline-triggered fast-path, radius expansion.
    // Without surfacing it the rider sees a frozen spinner while the
    // matcher cycles through 3+ drivers; with it, the matching screen
    // can say "Expanding to 5 km" / "Trying another driver".
    socket
      ..off('ride:matcher_progress')
      ..on('ride:matcher_progress', (data) {
        if (data is! Map<String, dynamic>) return;
        final attempt = (data['attempt'] as num?)?.toInt() ?? 0;
        final driversTried = (data['driversTried'] as num?)?.toInt() ?? 0;
        final driversRemaining =
            (data['driversRemaining'] as num?)?.toInt() ?? 0;
        final radiusKm = (data['radiusKm'] as num?)?.toDouble() ?? 0;
        ref.container.read(matcherProgressProvider.notifier).state =
            MatcherProgress(
          attempt: attempt,
          driversTried: driversTried,
          driversRemaining: driversRemaining,
          radiusKm: radiusKm,
        );
        ref.container.read(driversNotifiedProvider.notifier).state =
            driversTried;
      });

    // ── Route changes (rider added / cancelled a stop) ──────────────────
    // Backend emits `ride:route_updated` to the room when stops change.
    // The event payload doesn't carry the new stops list, so we re-fetch
    // the full ride and re-seed `tripStopsProvider` — the AddStopScreen
    // (and any future "stops list" widget) renders from there.
    socket
      ..off('ride:route_updated')
      ..on('ride:route_updated', (data) {
        final rideId = ref.container.read(activeRideIdProvider);
        if (rideId == null || rideId.isEmpty) return;
        ref.container.read(rideServiceProvider).getRide(rideId).then((json) {
          try {
            final stops = (json['stops'] as List<dynamic>?)
                    ?.whereType<Map<String, dynamic>>()
                    .map(RideStop.fromJson)
                    .toList() ??
                const <RideStop>[];
            ref.container.read(tripStopsProvider.notifier).seed(
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
      final activeRideId = ref.container.read(activeRideIdProvider);
      if (activeRideId == null) return;
      final eventRideId = data['rideId'] as String? ?? data['id'] as String?;
      if (eventRideId != null && eventRideId != activeRideId) return;
      final lat = (data['latitude'] ?? data['lat']) as num?;
      final lng = (data['longitude'] ?? data['lng']) as num?;
      if (lat == null || lng == null) return;
      final heading = (data['heading'] ?? data['bearing']) as num?;
      ref.container.read(liveDriverPositionProvider.notifier).state = LiveDriverPosition(
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        heading: heading?.toDouble(),
        updatedAt: DateTime.now(),
      );
    }

    socket
      ..off('driver:location')
      ..on('driver:location', handleDriverLocation);

    // ── Live artisan tracking ───────────────────────────────────────────
    // Backend emits `job:artisan:location` every time the artisan posts a
    // REST location heartbeat (every 4s while online). We push the fix
    // into [liveArtisanPositionProvider] for the tracking-map widget to
    // render. Gated on `trackedJobIdProvider` so only the screen actively
    // showing a job receives marker updates — drops re-broadcasts for any
    // other in-flight job the same client account might have.
    void handleArtisanLocation(dynamic data) {
      if (data is! Map<String, dynamic>) return;
      final eventJobId = data['jobId'] as String?;
      final tracked = ref.container.read(trackedJobIdProvider);
      if (eventJobId == null || tracked == null || eventJobId != tracked) {
        return;
      }
      final lat = (data['latitude'] ?? data['lat']) as num?;
      final lng = (data['longitude'] ?? data['lng']) as num?;
      if (lat == null || lng == null) return;
      ref.container.read(liveArtisanPositionProvider.notifier).state =
          LiveArtisanPosition(
        jobId: eventJobId,
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        updatedAt: DateTime.now(),
      );
    }

    socket
      ..off('job:artisan:location')
      ..on('job:artisan:location', handleArtisanLocation);

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
          ref.container.invalidate(jobDetailProvider(jobId));
          ref.container.invalidate(bidsForJobProvider(jobId));
          ref.container.invalidate(activeJobProvider(jobId));
        }

        if (ref.container.exists(activityNotifierProvider)) {
          ref.container.read(activityNotifierProvider.notifier).reload();
        }
        if (ref.container.exists(activityHistoryProvider)) {
          ref.container.read(activityHistoryProvider.notifier).silentReload();
        }
        ref.container.read(navBadgeProvider.notifier).increment('/activity');
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
    socket
      ..off('job:artisan_confirmed')
      ..on('job:artisan_confirmed', (data) {
      developer.log('Received job:artisan_confirmed event', name: 'WS');
      try {
        final etaLabel = data is Map<String, dynamic>
            ? data['etaLabel'] as String? ?? ''
            : '';
        if (ref.container.exists(bidDetailActionProvider)) {
          ref
              .read(bidDetailActionProvider.notifier)
              .onArtisanConfirmed(etaLabel: etaLabel);
        }
      } catch (e) {
        developer.log('Failed to handle job:artisan_confirmed: $e',
            name: 'WS', level: 900);
      }
    });

    // ── New / updated bid on a job ───────────────────────────────────────
    // Backend emits `job:bid:received` (new submission) and
    // `job:bid:updated` (edit). The legacy `job:bid_new` is kept as a
    // fallback in case any older deploy is still running. All three carry
    // the same shape now: jobId / bidId / amount / artisanAverageRating /
    // artisanRatingCount / etc. We invalidate the bid list so the next
    // read picks up the freshest aggregate from /jobs/:id/bids.
    socket
      ..off('job:bid:received')
      ..off('job:bid:updated')
      ..off('job:bid_new')
      ..on('job:bid:received', (data) {
        developer.log('Received job:bid:received event', name: 'WS');
        try {
          final jobId = data is Map<String, dynamic>
              ? (data['jobId'] as String? ?? data['id'] as String?)
              : null;
          if (jobId != null) {
            ref.container.invalidate(jobDetailProvider(jobId));
            ref.container.invalidate(bidsForJobProvider(jobId));
          }
          if (ref.container.exists(activityNotifierProvider)) {
            ref.container.read(activityNotifierProvider.notifier).reload();
          }
          ref.container.read(navBadgeProvider.notifier).increment('/activity');
        } catch (e) {
          developer.log('Failed to handle job:bid:received: $e',
              name: 'WS', level: 900);
        }
      })
      ..on('job:bid:updated', (data) {
        developer.log('Received job:bid:updated event', name: 'WS');
        try {
          final jobId = data is Map<String, dynamic>
              ? (data['jobId'] as String? ?? data['id'] as String?)
              : null;
          if (jobId != null) {
            ref.container.invalidate(jobDetailProvider(jobId));
            ref.container.invalidate(bidsForJobProvider(jobId));
          }
        } catch (e) {
          developer.log('Failed to handle job:bid:updated: $e',
              name: 'WS', level: 900);
        }
      })
      ..on('job:bid_new', (data) {
        developer.log('Received job:bid_new event (legacy)', name: 'WS');
        try {
          final jobId = data is Map<String, dynamic>
              ? (data['jobId'] as String? ?? data['id'] as String?)
              : null;
          if (jobId != null) {
            ref.container.invalidate(jobDetailProvider(jobId));
            ref.container.invalidate(bidsForJobProvider(jobId));
          }
          if (ref.container.exists(activityNotifierProvider)) {
            ref.container.read(activityNotifierProvider.notifier).reload();
          }
          ref.container.read(navBadgeProvider.notifier).increment('/activity');
        } catch (e) {
          developer.log('Failed to handle job:bid_new: $e',
              name: 'WS', level: 900);
        }
      });

    // ── New notification ─────────────────────────────────────────────────
    socket
      ..off('notification:new')
      ..on('notification:new', (data) {
      developer.log('Received notification:new event', name: 'WS');
      try {
        if (ref.container.exists(notifsProvider)) {
          ref.container.read(notifsProvider.notifier).reload();
        }
        ref.container.read(navBadgeProvider.notifier).increment('/profile');
      } catch (e) {
        developer.log('Failed to handle notification:new: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Profile updated ──────────────────────────────────────────────────
    socket
      ..off('profile:updated')
      ..on('profile:updated', (data) {
      developer.log('Received profile:updated event', name: 'WS');
      try {
        ref.container.read(clientAuthControllerProvider.notifier).refreshProfile();
      } catch (e) {
        developer.log('Failed to handle profile:updated: $e',
            name: 'WS', level: 900);
      }
    });

    // ── Rating prompt ────────────────────────────────────────────────────
    // Backend emits `rating:prompt` to the client socket room when a
    // ride/job finalises, so a foreground user gets the rate sheet live
    // without depending on the FCM push (which won't deliver while the
    // app is open and connected).
    final shownRatingFor = <String>{};
    void handleRatingPrompt(dynamic data) {
      developer.log('Received rating:prompt: $data', name: 'WS');
      if (data is! Map<String, dynamic>) return;
      final bookingType = data['bookingType'] as String?;
      final bookingId = (data['bookingId'] ??
          data['rideId'] ??
          data['jobId']) as String?;
      if (bookingType == null || bookingId == null || bookingId.isEmpty) {
        return;
      }
      // Per-process dedup — a reconnect-redelivered emit or an FCM tap
      // arriving milliseconds later must not stack a second sheet.
      if (!shownRatingFor.add(bookingId)) return;

      final ctx =
          ref.container.read(routerProvider).routerDelegate.navigatorKey.currentContext;
      if (ctx == null) return;

      Future<void> openSheet() async {
        if (bookingType == 'ride') {
          var firstName = 'Driver';
          try {
            final raw =
                await ref.container.read(rideServiceProvider).getRide(bookingId);
            final driver = raw['driver'];
            if (driver is Map<String, dynamic>) {
              final name = driver['name'] as String?;
              if (name != null && name.trim().isNotEmpty) {
                firstName = name.trim().split(RegExp(r'\s+')).first;
              }
            }
          } catch (e) {
            developer.log('hydrate ride for rating failed: $e',
                name: 'WS', level: 800);
          }
          if (!ctx.mounted) return;
          await showRateRideSheet(
            ctx,
            rideId: bookingId,
            driverFirstName: firstName,
          );
        } else if (bookingType == 'artisan_job' || bookingType == 'job') {
          var firstName = 'Artisan';
          try {
            final raw =
                await ref.container.read(jobServiceProvider).getJob(bookingId);
            final artisan = raw['artisan'];
            if (artisan is Map<String, dynamic>) {
              final name = (artisan['displayName'] ??
                  artisan['businessName'] ??
                  artisan['fullName'] ??
                  artisan['name']) as String?;
              if (name != null && name.trim().isNotEmpty) {
                firstName = name.trim().split(RegExp(r'\s+')).first;
              }
            }
          } catch (e) {
            developer.log('hydrate job for rating failed: $e',
                name: 'WS', level: 800);
          }
          if (!ctx.mounted) return;
          await showRateJobSheet(
            ctx,
            jobId: bookingId,
            artisanFirstName: firstName,
          );
          // After the client rates, land them on the request details
          // page — the natural place to review the booking, message
          // the artisan, or download the receipt. Mirrors the post-
          // payment dialog's flow.
          if (ctx.mounted) {
            ref
                .read(routerProvider)
                .go(AppRoutes.jobDetailPath(bookingId));
          }
        } else {
          shownRatingFor.remove(bookingId);
        }
      }

      unawaited(openSheet());
    }

    socket
      ..off('rating:prompt')
      ..on('rating:prompt', handleRatingPrompt);
  });
}
