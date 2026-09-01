import 'dart:async';
import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart'
    show RideRouteUpdate, RideStop;

import '../../app/router.dart' show AppRoutes, routerProvider;
import '../../features/auth/providers/auth_controller.dart';
import 'auth_session_identity_provider.dart';
import '../../features/activity/providers/activity_history_provider.dart';
import '../../features/activity/providers/activity_provider.dart';
import '../../features/home/providers/home_provider.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../../features/ride/providers/edit_trip_provider.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../../features/ride/utils/ride_error_messages.dart';
import '../../features/ride/widgets/rate_ride_sheet.dart';
import '../../features/ride/widgets/ride_cancelled_dialog.dart';
import '../../features/services/providers/active_job_provider.dart';
import '../../features/services/providers/bid_detail_provider.dart';
import '../../features/services/providers/bid_list_provider.dart';
import '../../features/services/providers/job_detail_provider.dart';
import '../../features/services/widgets/rate_job_sheet.dart';
import '../di/providers.dart';
import 'nav_badge_provider.dart';
import 'provider_location_notice_provider.dart';

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
  // Recreate and dispose the transport on every full session replacement.
  ref.watch(currentClientAuthSessionIdentityProvider);
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
  var hasConnectedOnce = false;
  socket.connectionStream.listen((connected) {
    ref.container.read(socketConnectedProvider.notifier).state = connected;
    if (!connected) return;
    if (hasConnectedOnce && ref.container.exists(homeRecentActivityProvider)) {
      // Reconcile a session-cached Home preview after a genuine reconnect.
      // The initial connection is excluded to avoid duplicating Home's first
      // one-shot load.
      ref.container.invalidate(homeRecentActivityProvider);
    }
    hasConnectedOnce = true;
    final rideId = ref.container.read(activeRideIdProvider);
    if (rideId != null && rideId.isNotEmpty) {
      developer.log('Socket connected — joining ride room $rideId', name: 'WS');
      socket.emit('client:track:ride', {
        'rideId': rideId,
        'replayProgress': true,
      });
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

  // Attach all domain handlers via `onAfterCreate` so they re-bind on every
  // post-dispose reconnect (server restart, lifecycle observer kicking the
  // socket on resume, auth-refresh re-create). The previous version used
  // `socket.connect().then(...)` which fires exactly once — after a Render
  // redeploy mid-session, the client reconnected but `ride:state`,
  // `ride:matcher_progress` etc. were no longer registered, so the rider
  // saw the connection succeed and the matching UI silently froze.
  void attachHandlers() {
    debugPrint('[WS] (re-)attaching client domain handlers');

    // A booking can arrive through both its lightweight and canonical socket
    // events. Refresh the session-cached home preview once per authoritative
    // status so duplicate packets do not multiply history reads.
    final refreshedHomeActivityEvents = <String>{};
    void invalidateHomeActivityOnce(String type, String? id, String status) {
      final normalizedId = id?.trim() ?? '';
      if (normalizedId.isEmpty || status.isEmpty) return;
      if (!refreshedHomeActivityEvents.add('$type:$normalizedId:$status')) {
        return;
      }
      ref.container.invalidate(homeRecentActivityProvider);
    }

    // Event names are useful diagnostics; payloads are not logged because
    // ride snapshots can contain exact addresses, coordinates, and identity.
    socket.onAnyEvent((event, _) {
      developer.log('[event] $event', name: 'WS');
    });

    ProviderLocationNotice? locationNoticeFrom(
      dynamic data, {
      required bool escalated,
    }) {
      if (data is! Map) return null;
      final payload = Map<String, dynamic>.from(data);
      final rideId = payload['rideId']?.toString().trim();
      if (rideId != null && rideId.isNotEmpty) {
        return ProviderLocationNotice(
          bookingId: rideId,
          bookingType: 'ride',
          escalated: escalated,
        );
      }
      final jobId = payload['jobId']?.toString().trim();
      if (jobId != null && jobId.isNotEmpty) {
        return ProviderLocationNotice(
          bookingId: jobId,
          bookingType: 'job',
          escalated: escalated,
        );
      }
      return null;
    }

    void handleProviderLocationDegraded(dynamic data) {
      final notice = locationNoticeFrom(data, escalated: false);
      if (notice != null) {
        ref.container.read(providerLocationNoticeProvider.notifier).state =
            notice;
      }
    }

    void handleProviderLocationEscalated(dynamic data) {
      final notice = locationNoticeFrom(data, escalated: true);
      if (notice != null) {
        ref.container.read(providerLocationNoticeProvider.notifier).state =
            notice;
      }
    }

    void handleProviderLocationRecovered(dynamic data) {
      final recovered = locationNoticeFrom(data, escalated: false);
      if (recovered == null) return;
      final current = ref.container.read(providerLocationNoticeProvider);
      if (current?.bookingId == recovered.bookingId &&
          current?.bookingType == recovered.bookingType) {
        ref.container.read(providerLocationNoticeProvider.notifier).state =
            null;
      }
    }

    socket
      ..off('provider:location_degraded')
      ..off('provider:location_escalated')
      ..off('provider:location_recovered')
      ..on('provider:location_degraded', handleProviderLocationDegraded)
      ..on('provider:location_escalated', handleProviderLocationEscalated)
      ..on('provider:location_recovered', handleProviderLocationRecovered);

    // Apply a `ride:state` snapshot — the backend's canonical event that
    // fires on every ride state change (status transition, fare update,
    // location bump while active, cancel, completion). Drives every ride
    // provider on the rider side: matched driver, booking phase, tracking
    // phase, and the live driver marker.
    //
    // Replaces the legacy `ride:accepted` + `ride:status` listeners and
    // the multi-name `ride:driver_location` / `ride:location` guesses;
    // backend's M-1 spec guarantees one event with a full snapshot.
    DateTime? parseSocketDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    void applyRideSnapshot(Map<String, dynamic> data) {
      final snapshotRideId = (data['rideId'] ?? data['id'])?.toString();
      final activeRideId = ref.container.read(activeRideIdProvider);
      if (snapshotRideId != null &&
          snapshotRideId.isNotEmpty &&
          activeRideId != null &&
          activeRideId.isNotEmpty &&
          snapshotRideId != activeRideId) {
        developer.log(
          'Ignoring stale ride:state for $snapshotRideId; '
          'active ride is $activeRideId',
          name: 'WS',
        );
        return;
      }
      final driver =
          data['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};
      // Driver name may arrive as a single `name` field or split into
      // first/last; fall back gracefully so the rider doesn't see "Driver".
      final firstName = driver['firstName'] as String?;
      final lastName = driver['lastName'] as String?;
      final assembledName = (firstName != null || lastName != null)
          ? [firstName, lastName].whereType<String>().join(' ').trim()
          : null;
      final fare = RideFareFields.fromSnapshot(data);
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
        phone: (driver['phone'] as String?) ??
            (driver['maskedPhone'] as String?) ??
            '',
        vehicleTier: driver['vehicleTier'] as String? ?? '',
        baseFarePesewas: fare.baseFarePesewas,
        distanceFarePesewas: fare.distanceFarePesewas,
        distanceKm: fare.distanceKm,
        bookingFeePesewas: fare.bookingFeePesewas,
        promoDiscountPesewas: fare.promoDiscountPesewas,
        loyaltyDiscountPesewas: fare.loyaltyDiscountPesewas,
        toll: fare.toll,
        vehicleShortName: driver['vehicleShortName'] as String? ?? '',
        confirmedFarePesewas: fare.totalFarePesewas,
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
      final rideId = (data['rideId'] ?? data['id'])?.toString();
      invalidateHomeActivityOnce('ride', rideId, status);
      if (status != 'requested' && status.isNotEmpty) {
        ref.container.read(rideOfferDecisionCountdownProvider.notifier).clear();
      }
      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'no_drivers') {
        final notice = ref.container.read(providerLocationNoticeProvider);
        if (notice?.bookingType == 'ride' && notice?.bookingId == rideId) {
          ref.container.read(providerLocationNoticeProvider.notifier).state =
              null;
        }
      }
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
          ref.container.read(rideMatchedViaSocketProvider.notifier).state =
              true;
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

      // New snapshots carry the destination route revision. Apply only a
      // strictly newer projection; legacy snapshots parse as revision zero
      // and can never roll back a confirmed destination.
      try {
        applyActiveRideRouteUpdate(
          ref.container.read,
          RideRouteUpdate.fromRideJson(data),
        );
      } on FormatException {
        // Slim/legacy ride:state payloads legitimately omit route endpoints.
      }

      // Tracking phase (only when the ride is past `accepted`).
      switch (status) {
        case 'driver_en_route':
          ref.container.read(rideArrivalAnchorProvider.notifier).state = null;
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.enRoute;
        case 'arrived_at_pickup' || 'arrived':
          final arrivedAt = parseSocketDate(
            data['arrivedAtPickupAt'] ?? data['statusChangedAt'],
          );
          ref.container.read(rideArrivalAnchorProvider.notifier).state =
              arrivedAt ??
                  ref.container.read(rideArrivalAnchorProvider) ??
                  DateTime.now();
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.arrived;
        case 'in_progress':
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.inProgress;
        case 'completed':
          unawaited(
            ref.container.read(rideBookingAttemptStoreProvider).clear(),
          );
          // Build/preserve the receipt, clear every next-ride input, then flip
          // the phase so the tracking listener cannot navigate early and the
          // just-completed pickup cannot leak into the rider's next request.
          applyCompletedRideSnapshot(ref.container.read, data);
          if (ref.container.exists(activityNotifierProvider)) {
            ref.container.read(activityNotifierProvider.notifier).reload();
          }
          if (ref.container.exists(activityHistoryProvider)) {
            ref.container.read(activityHistoryProvider.notifier).silentReload();
          }
          ref.container.read(navBadgeProvider.notifier).increment('/activity');
        case 'cancelled' || 'no_drivers':
          if (status == 'cancelled') {
            unawaited(
              ref.container.read(rideBookingAttemptStoreProvider).clear(),
            );
          }
          ref.container.read(rideArrivalAnchorProvider.notifier).state = null;
          // Flip BOTH provider tracks so wherever the rider is sitting —
          // matching screen (bookingPhase=searching) or tracking screen
          // (rideTrackingPhase=enRoute/arrived/inProgress) — they get
          // routed away. Previously only bookingPhase moved, so a
          // mid-trip driver-cancel left the rider stuck on the live map
          // because the tracking screen watches rideTrackingPhase.
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.cancelled;

          final reason = (data['cancellationReason'] as String?) ?? '';
          final cancelledBy = (data['cancelledBy'] as String?) ?? '';
          final friendlyMessage = rideSocketCancellationMessage(
            status: status,
            reason: reason,
            cancelledBy: cancelledBy,
          );
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
        debugPrint(
          '[LIVE-TRACK] ride:state seeded driver position ($dLat, $dLng)',
        );
        ref.container.read(liveDriverPositionProvider.notifier).state =
            LiveDriverPosition(
          latitude: dLat.toDouble(),
          longitude: dLng.toDouble(),
          heading: heading?.toDouble(),
          updatedAt: DateTime.now(),
        );
      } else {
        debugPrint(
          '[LIVE-TRACK] ride:state had no currentLat/currentLng — '
          'marker waits for next driver:location fix',
        );
      }
    }

    socket
      ..off('ride:state')
      ..on('ride:state', (data) {
        // Broad Map guard + normalise: Socket.IO frequently delivers
        // Map<dynamic,dynamic>, which the old narrow Map<String,dynamic> guard
        // silently dropped — leaving the rider stuck on the map when the driver
        // cancelled (the cancelled snapshot was discarded before reaching
        // applyRideSnapshot). Mirrors the broad guard already used by
        // driver:location and ride:matcher_progress.
        if (data is! Map) return;
        final snap = Map<String, dynamic>.from(data);
        try {
          applyRideSnapshot(snap);
        } catch (e) {
          developer.log(
            'Failed to apply ride:state snapshot (${e.runtimeType})',
            name: 'WS',
            level: 900,
          );
        }
      });

    // Lightweight, low-latency status event. The backend emits this before the
    // heavier canonical ride:state snapshot is built. Use it for immediate UI
    // phase changes (Arrived / Start Trip), then let ride:state reconcile the
    // full driver/fare/location payload when it lands.
    void applyFastRideStatus(dynamic data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final activeRideId = ref.container.read(activeRideIdProvider);
      if (activeRideId == null || activeRideId.isEmpty) return;

      final eventRideId = (map['rideId'] ?? map['id']) as String? ?? '';
      if (eventRideId.isNotEmpty && eventRideId != activeRideId) return;

      final status = map['status'] as String? ?? '';
      invalidateHomeActivityOnce(
        'ride',
        eventRideId.isEmpty ? activeRideId : eventRideId,
        status,
      );
      if (status == 'completed' || status == 'cancelled') {
        unawaited(ref.container.read(rideBookingAttemptStoreProvider).clear());
      }
      switch (status) {
        case 'driver_en_route':
          ref.container
              .read(rideOfferDecisionCountdownProvider.notifier)
              .clear();
          ref.container.read(bookingPhaseProvider.notifier).accepted();
          ref.container.read(rideArrivalAnchorProvider.notifier).state = null;
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.enRoute;
        case 'arrived_at_pickup' || 'arrived':
          ref.container.read(bookingPhaseProvider.notifier).accepted();
          ref.container.read(rideArrivalAnchorProvider.notifier).state =
              parseSocketDate(
                    map['arrivedAtPickupAt'] ?? map['statusChangedAt'],
                  ) ??
                  DateTime.now();
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.arrived;
        case 'in_progress':
          ref.container.read(bookingPhaseProvider.notifier).accepted();
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.inProgress;
        case 'completed':
          // Completion needs the full receipt/fare snapshot. Ask REST to hydrate
          // immediately instead of waiting for the maintainer's next poll, but
          // let the hydrate path flip the phase after it has populated receipt.
          unawaited(
            hydrateActiveRideFromRest(
              ref.container.read,
              ref.container.read(rideServiceProvider),
              activeRideId,
            ),
          );
        case 'cancelled' || 'no_drivers':
          ref.container
              .read(rideOfferDecisionCountdownProvider.notifier)
              .clear();
          ref.container.read(rideArrivalAnchorProvider.notifier).state = null;
          ref.container.read(bookingFailureMessageProvider.notifier).state =
              status == 'no_drivers'
                  ? noDriversAvailableMessage
                  : 'This ride was cancelled.';
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.cancelled;
          ref.container.read(bookingPhaseProvider.notifier).fail();
      }
    }

    socket
      ..off('ride:status')
      ..off('ride:status:changed')
      ..on('ride:status', applyFastRideStatus)
      ..on('ride:status:changed', applyFastRideStatus);

    // Authoritative cancel signal. The rider only consumes `ride:state` for
    // tracking, so a driver/support cancel could be missed if that snapshot
    // wasn't delivered or the rider isn't on the tracking screen. This handler
    // ALWAYS surfaces the cancellation with a blocking dialog → home. The
    // rider's own cancel (cancelledBy == 'client') is skipped — they navigate
    // from their own flow.
    final shownCancelledFor = <String>{};
    socket
      ..off('ride:cancelled')
      ..on('ride:cancelled', (data) {
        if (data is! Map) return;
        final map = Map<String, dynamic>.from(data);
        final cancelledBy = (map['cancelledBy'] as String?) ?? '';
        final rideId = (map['rideId'] ?? map['id']) as String? ?? '';
        invalidateHomeActivityOnce('ride', rideId, 'cancelled');
        if (cancelledBy == 'client') return;
        if (rideId.isNotEmpty && !shownCancelledFor.add(rideId)) return;
        unawaited(ref.container.read(rideBookingAttemptStoreProvider).clear());

        final reason = (map['reason'] as String?) ?? '';
        final noDrivers = _isNoDriversCancellation(reason: reason);
        if (noDrivers) {
          // Backend system expiry emits `ride:cancelled` first, followed by
          // `ride:status no_drivers` and `ride:state`. If those later packets
          // are missed, resetting bookingPhase to idle leaves the matching
          // screen mounted but visually "searching" forever. Treat the
          // no-driver cancellation as a terminal matching failure immediately.
          ref.container.read(matchedDriverProvider.notifier).state = null;
          ref.container.read(rideArrivalAnchorProvider.notifier).state = null;
          ref.container.read(bookingFailureMessageProvider.notifier).state =
              noDriversAvailableMessage;
          ref.container.read(bookingPhaseProvider.notifier).fail();
          ref.container.read(rideTrackingPhaseProvider.notifier).state =
              RideTrackingPhase.cancelled;
          if (ref.container.exists(activityHistoryProvider)) {
            ref.container.read(activityHistoryProvider.notifier).silentReload();
          }
          return;
        }

        final message = rideSocketCancellationMessage(
          reason: reason,
          cancelledBy: cancelledBy,
        );

        // Clear local ride state so the next booking starts clean. Don't flip
        // rideTrackingPhase here — the dialog + home navigation is the single
        // user-facing exit, avoiding a snackbar/auto-nav race with the
        // tracking screen.
        ref.container.read(matchedDriverProvider.notifier).state = null;
        ref.container.read(rideArrivalAnchorProvider.notifier).state = null;
        if (ref.container.exists(bookingPhaseProvider)) {
          ref.container.read(bookingPhaseProvider.notifier).reset();
        }
        if (ref.container.exists(activityHistoryProvider)) {
          ref.container.read(activityHistoryProvider.notifier).silentReload();
        }

        final router = ref.container.read(routerProvider);
        final ctx = router.routerDelegate.navigatorKey.currentContext;
        if (ctx == null) return;
        showRideCancelledDialog(
          ctx,
          message,
          onConfirm: () => router.go(AppRoutes.home),
        );
      });

    // Advisory delay signal. This is deliberately NOT treated as a
    // cancellation: no provider resets, no route changes. It exists so the
    // backend can stop hard-cancelling delayed-but-still-valid rides while the
    // rider still gets clear feedback.
    socket
      ..off('ride:driver_delayed')
      ..on('ride:driver_delayed', (data) {
        if (data is! Map) return;
        final map = Map<String, dynamic>.from(data);
        final activeRideId = ref.container.read(activeRideIdProvider);
        final eventRideId = (map['rideId'] ?? map['id']) as String?;
        if (eventRideId != null &&
            activeRideId != null &&
            eventRideId != activeRideId) {
          return;
        }
        const message = rideSocketDriverDelayMessage;
        developer.log('ride:driver_delayed — $message', name: 'WS');

        final router = ref.container.read(routerProvider);
        final ctx = router.routerDelegate.navigatorKey.currentContext;
        if (ctx == null) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
      });

    // Backend pushes `ride:matcher_progress` on every dispatch attempt —
    // initial broadcast, decline-triggered fast-path, radius expansion.
    // Without surfacing it the rider sees a frozen spinner while the
    // matcher cycles through 3+ drivers; with it, the matching screen
    // can say "Expanding to 5 km" / "Trying another driver".
    socket
      ..off('ride:matcher_progress')
      ..on('ride:matcher_progress', (data) {
        // Accept any Map shape — Socket.IO occasionally hands us
        // Map<dynamic, dynamic> instead of Map<String, dynamic>, which the
        // narrower type guard silently drops. The guard was masking
        // matcher_progress events on real-device tests; cast through Map
        // and read keys defensively instead.
        if (data is! Map) {
          developer.log(
            'matcher_progress: rejected non-map payload',
            name: 'WS',
          );
          return;
        }
        final map = Map<String, dynamic>.from(data);
        final activeRideId = ref.container.read(activeRideIdProvider);
        final eventRideId = (map['rideId'] ?? map['id'])?.toString();
        if (eventRideId == null ||
            eventRideId.isEmpty ||
            activeRideId == null ||
            eventRideId != activeRideId) {
          return;
        }
        final attempt = (map['attempt'] as num?)?.toInt() ?? 0;
        final currentProgress = ref.container.read(matcherProgressProvider);
        if (attempt > 0 &&
            currentProgress != null &&
            currentProgress.attempt > attempt) {
          developer.log(
            'matcher_progress: ignored stale attempt=$attempt '
            'current=${currentProgress.attempt}',
            name: 'WS',
          );
          return;
        }
        final driversTried = (map['driversTried'] as num?)?.toInt() ?? 0;
        final driversRemaining =
            (map['driversRemaining'] as num?)?.toInt() ?? 0;
        final radiusKm = (map['radiusKm'] as num?)?.toDouble() ?? 0;
        final expanded = map['expanded'] == true;
        final reason = parseMatcherReason(map['reason'] as String?);
        if (currentProgress != null &&
            attempt == currentProgress.attempt &&
            (radiusKm < currentProgress.radiusKm ||
                (radiusKm == currentProgress.radiusKm &&
                    currentProgress.expanded &&
                    !expanded))) {
          developer.log(
            'matcher_progress: ignored regressive same-attempt radius/state',
            name: 'WS',
          );
          return;
        }
        developer.log(
          'matcher_progress: reason=$reason attempt=$attempt '
          'tried=$driversTried remaining=$driversRemaining '
          'radiusKm=$radiusKm expanded=$expanded',
          name: 'WS',
        );
        ref.container.read(matcherProgressProvider.notifier).state =
            MatcherProgress(
          attempt: attempt,
          driversTried: driversTried,
          driversRemaining: driversRemaining,
          radiusKm: radiusKm,
          expanded: expanded,
          reason: reason,
        );
        ref.container.read(driversNotifiedProvider.notifier).state =
            driversTried;
        if (reason == MatcherReason.decline ||
            reason == MatcherReason.timeout) {
          final countdown = ref.container.read(
            rideOfferDecisionCountdownProvider,
          );
          // Redispatch publishes attempt N before its offer is receipted. Clear
          // an older driver's countdown, but never let replayed context for the
          // same active attempt erase its authoritative decision window.
          if (countdown == null || attempt > countdown.attempt) {
            ref.container
                .read(rideOfferDecisionCountdownProvider.notifier)
                .clear();
          }
        }
      });

    // A real driver countdown begins only after the provider's authenticated
    // receipt activates the database decision deadline. This event contains
    // no driver/offer identity; it is safe for the rider room and replayed on
    // reconnect by client:track:ride.
    socket
      ..off('ride:offer_received')
      ..on('ride:offer_received', (data) {
        if (data is! Map) return;
        final map = Map<String, dynamic>.from(data);
        final activeRideId = ref.container.read(activeRideIdProvider);
        final eventRideId = map['rideId']?.toString();
        if (eventRideId == null ||
            eventRideId.isEmpty ||
            activeRideId == null ||
            eventRideId != activeRideId) {
          return;
        }
        final phase = ref.container.read(bookingPhaseProvider);
        if (ref.container.read(rideSearchCancellationRequestedProvider) ||
            (phase != BookingPhase.searching &&
                phase != BookingPhase.driverFound)) {
          return;
        }
        final serverNow = DateTime.tryParse(map['serverNow']?.toString() ?? '');
        final decisionExpiresAt = DateTime.tryParse(
          map['decisionExpiresAt']?.toString() ?? '',
        );
        final totalSeconds =
            (map['acceptanceWindowSeconds'] as num?)?.toInt() ?? 30;
        final attempt = (map['attempt'] as num?)?.toInt() ??
            ref.container.read(matcherProgressProvider)?.attempt ??
            1;
        final progressAttempt =
            ref.container.read(matcherProgressProvider)?.attempt ?? 0;
        final countdownAttempt =
            ref.container.read(rideOfferDecisionCountdownProvider)?.attempt ??
                0;
        final knownAttempt = progressAttempt > countdownAttempt
            ? progressAttempt
            : countdownAttempt;
        if (serverNow == null ||
            decisionExpiresAt == null ||
            !decisionExpiresAt.isAfter(serverNow) ||
            attempt < knownAttempt) {
          return;
        }
        ref.container.read(bookingPhaseProvider.notifier).driverFound();
        ref.container.read(rideOfferDecisionCountdownProvider.notifier).start(
              attempt: attempt,
              serverNow: serverNow,
              decisionExpiresAt: decisionExpiresAt,
              totalSeconds: totalSeconds,
            );
      });

    // Authoritative combined replay. This is also embedded in the REST ride
    // snapshot so a missed room event cannot strand the rider at Searching.
    socket
      ..off('ride:matching_state')
      ..on('ride:matching_state', (data) {
        if (data is! Map) return;
        final map = Map<String, dynamic>.from(data);
        final activeRideId = ref.container.read(activeRideIdProvider);
        final eventRideId = map['rideId']?.toString();
        if (activeRideId == null ||
            eventRideId == null ||
            eventRideId != activeRideId) {
          return;
        }
        final phase = ref.container.read(bookingPhaseProvider);
        if (ref.container.read(rideSearchCancellationRequestedProvider) ||
            (phase != BookingPhase.searching &&
                phase != BookingPhase.driverFound)) {
          return;
        }
        applyRideMatchingState(ref.container.read, map);
      });

    // ── Route changes (destination replacement / legacy stop updates) ────
    bool applyRouteProjection(RideRouteUpdate update) {
      final applied = applyActiveRideRouteUpdate(ref.container.read, update);
      if (!applied) return false;
      final destination = update.destination!;
      ref.container.read(tripStopsProvider.notifier).updateStopAddress(
            'destination',
            destination.address,
            lat: destination.lat,
            lng: destination.lng,
          );
      return true;
    }

    Future<void> refetchRouteProjection(
      String rideId, {
      int? advertisedRevision,
    }) async {
      final activeRideId = ref.container.read(activeRideIdProvider);
      if (activeRideId != rideId) return;
      final current = ref.container.read(activeRideRouteUpdateProvider);
      if (advertisedRevision != null &&
          current?.rideId == rideId &&
          advertisedRevision <= current!.routeRevision) {
        return;
      }
      try {
        final json =
            await ref.container.read(rideServiceProvider).getRide(rideId);
        if (ref.container.read(activeRideIdProvider) != rideId) return;
        final update = RideRouteUpdate.fromRideJson(json);
        if (advertisedRevision != null &&
            update.routeRevision < advertisedRevision) {
          developer.log(
            'Route refetch lagged event revision $advertisedRevision '
            '(snapshot=${update.routeRevision})',
            name: 'WS',
            level: 800,
          );
          return;
        }
        applyRouteProjection(update);

        final stops = (json['stops'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(RideStop.fromJson)
                .toList() ??
            const <RideStop>[];
        final route = update.destination;
        if (route != null) {
          ref.container.read(tripStopsProvider.notifier).seed(
            pickup: (
              address: json['pickupAddress'] as String?,
              lat: (json['pickupLat'] as num?)?.toDouble(),
              lng: (json['pickupLng'] as num?)?.toDouble(),
            ),
            destination: (
              address: route.address,
              lat: route.lat,
              lng: route.lng,
            ),
            existingStops: stops,
          );
        }
      } catch (error) {
        developer.log(
          'Route projection refetch failed: $error',
          name: 'WS',
          level: 800,
        );
      }
    }

    void handleDestinationChanged(dynamic data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final rideId = (map['rideId'] ?? map['id'])?.toString();
      final rawRevision = map['routeRevision'] ?? map['route_revision'];
      final revision = rawRevision is num
          ? rawRevision.toInt()
          : int.tryParse(rawRevision?.toString() ?? '');
      if (rideId == null || rideId.isEmpty) return;
      try {
        final update = RideRouteUpdate.fromJson(map);
        if (update.hasCompleteRouteProjection && applyRouteProjection(update)) {
          return;
        }
      } on FormatException {
        // A thin compatibility event intentionally falls through to REST.
      }
      unawaited(
        refetchRouteProjection(
          rideId,
          advertisedRevision: revision,
        ),
      );
    }

    void handleLegacyRouteUpdated(dynamic data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : const {};
      final rideId = (map['rideId'] ?? map['id'])?.toString() ??
          ref.container.read(activeRideIdProvider);
      if (rideId == null || rideId.isEmpty) return;
      final revision = map['routeRevision'] ?? map['route_revision'];
      unawaited(
        refetchRouteProjection(
          rideId,
          advertisedRevision: revision is num ? revision.toInt() : null,
        ),
      );
    }

    socket
      ..off('ride:destination_changed')
      ..off('ride:route_updated')
      ..on('ride:destination_changed', handleDestinationChanged)
      ..on('ride:route_updated', handleLegacyRouteUpdated);

    // ── Live driver location ─────────────────────────────────────────────
    // Per-fix marker updates. `ride:state` carries the full snapshot at a
    // ~5s cadence (throttled server-side); `driver:location` continues to
    // fire on every GPS bump so the marker animates smoothly between
    // snapshots. Gated on the active ride id so the rider's marker
    // doesn't jitter from unrelated ride traffic.
    void handleDriverLocation(dynamic data) {
      if (data is! Map) {
        debugPrint('[LIVE-TRACK] driver:location dropped — payload not Map');
        return;
      }
      final payload = Map<String, dynamic>.from(data);
      final activeRideId = ref.container.read(activeRideIdProvider);
      if (activeRideId == null) {
        debugPrint(
          '[LIVE-TRACK] driver:location dropped — no activeRideId set',
        );
        return;
      }
      final eventRideId =
          payload['rideId'] as String? ?? payload['id'] as String?;
      if (eventRideId != null && eventRideId != activeRideId) {
        debugPrint(
          '[LIVE-TRACK] driver:location dropped — rideId mismatch '
          '(event=$eventRideId active=$activeRideId)',
        );
        return;
      }
      final lat = (payload['latitude'] ?? payload['lat']) as num?;
      final lng = (payload['longitude'] ?? payload['lng']) as num?;
      if (lat == null || lng == null) {
        debugPrint(
          '[LIVE-TRACK] driver:location dropped — missing lat/lng in payload',
        );
        return;
      }
      final heading = (payload['heading'] ?? payload['bearing']) as num?;
      debugPrint(
        '[LIVE-TRACK] driver:location accepted ($lat, $lng) heading=$heading',
      );
      ref.container.read(liveDriverPositionProvider.notifier).state =
          LiveDriverPosition(
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
    // contract); older code emitted `job:status`, while authoritative client
    // cancellation emits `job:cancelled`. Listen to all three.
    void handleJobStatus(dynamic data, {String? fallbackStatus}) {
      developer.log('Received job:status event', name: 'WS');
      try {
        if (data is! Map) return;
        final map = Map<String, dynamic>.from(data);
        // If the payload carries a jobId, refresh that job's detail + bids
        // + active-job cache so any currently-open detail/summary/payment
        // screen updates live (including pending_payment → completed).
        final jobId = (map['jobId'] ?? map['id'])?.toString().trim();
        if (jobId != null && jobId.isNotEmpty) {
          ref.container.invalidate(jobDetailProvider(jobId));
          ref.container.invalidate(bidsForJobProvider(jobId));
          ref.container.invalidate(activeJobProvider(jobId));
          final status = map['status']?.toString() ?? fallbackStatus;
          invalidateHomeActivityOnce('job', jobId, status ?? 'updated');
          final notice = ref.container.read(providerLocationNoticeProvider);
          if ((status == 'completed' || status == 'cancelled') &&
              notice?.bookingType == 'job' &&
              notice?.bookingId == jobId) {
            ref.container.read(providerLocationNoticeProvider.notifier).state =
                null;
          }
        }

        if (ref.container.exists(activityNotifierProvider)) {
          ref.container.read(activityNotifierProvider.notifier).reload();
        }
        if (ref.container.exists(activityHistoryProvider)) {
          ref.container.read(activityHistoryProvider.notifier).silentReload();
        }
        ref.container.read(navBadgeProvider.notifier).increment('/activity');
      } catch (e) {
        developer.log(
          'Failed to handle job:status: $e',
          name: 'WS',
          level: 900,
        );
      }
    }

    socket
      ..off('job:status')
      ..off('job:status:changed')
      ..off('job:cancelled')
      ..on('job:status', (data) => handleJobStatus(data))
      ..on('job:status:changed', (data) => handleJobStatus(data))
      ..on(
        'job:cancelled',
        (data) => handleJobStatus(data, fallbackStatus: 'cancelled'),
      );

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
          developer.log(
            'Failed to handle job:artisan_confirmed: $e',
            name: 'WS',
            level: 900,
          );
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
          developer.log(
            'Failed to handle job:bid:received: $e',
            name: 'WS',
            level: 900,
          );
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
          developer.log(
            'Failed to handle job:bid:updated: $e',
            name: 'WS',
            level: 900,
          );
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
          developer.log(
            'Failed to handle job:bid_new: $e',
            name: 'WS',
            level: 900,
          );
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
          developer.log(
            'Failed to handle notification:new: $e',
            name: 'WS',
            level: 900,
          );
        }
      });

    // ── Profile updated ──────────────────────────────────────────────────
    socket
      ..off('profile:updated')
      ..on('profile:updated', (data) {
        developer.log('Received profile:updated event', name: 'WS');
        try {
          ref.container
              .read(clientAuthControllerProvider.notifier)
              .refreshProfile();
        } catch (e) {
          developer.log(
            'Failed to handle profile:updated: $e',
            name: 'WS',
            level: 900,
          );
        }
      });

    // ── Rating prompt ────────────────────────────────────────────────────
    // Backend emits `rating:prompt` to the client socket room when a
    // ride/job finalises, so a foreground user gets the rate sheet live
    // without depending on the FCM push (which won't deliver while the
    // app is open and connected).
    final shownRatingFor = <String>{};
    void handleRatingPrompt(dynamic data) {
      developer.log('Received rating:prompt', name: 'WS');
      if (data is! Map<String, dynamic>) return;
      final bookingType = data['bookingType'] as String?;
      final bookingId =
          (data['bookingId'] ?? data['rideId'] ?? data['jobId']) as String?;
      if (bookingType == null || bookingId == null || bookingId.isEmpty) {
        return;
      }
      // The in-app ride completion flow owns its rating step: summary first,
      // then the rating sheet on OK, then the receipt. If the rider is inside
      // that flow (tracking → payment → complete), auto-opening the sheet
      // here would cover the summary before they ever read their fare — the
      // exact bug this ordering fixes. The socket prompt only serves riders
      // who are elsewhere in the app when the ride finalises.
      if (bookingType == 'ride') {
        final location = ref.container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path;
        final inCompletionFlow = location == AppRoutes.rideComplete ||
            location == AppRoutes.rideTracking ||
            location == AppRoutes.ridePaymentPath(bookingId);
        if (inCompletionFlow) return;
      }

      // Per-process dedup — a reconnect-redelivered emit or an FCM tap
      // arriving milliseconds later must not stack a second sheet.
      if (!shownRatingFor.add(bookingId)) return;

      final ctx = ref.container
          .read(routerProvider)
          .routerDelegate
          .navigatorKey
          .currentContext;
      if (ctx == null) return;

      Future<void> openSheet() async {
        if (bookingType == 'ride') {
          var firstName = 'Driver';
          try {
            final raw = await ref.container
                .read(rideServiceProvider)
                .getRide(bookingId);
            final driver = raw['driver'];
            if (driver is Map<String, dynamic>) {
              final name = driver['name'] as String?;
              if (name != null && name.trim().isNotEmpty) {
                firstName = name.trim().split(RegExp(r'\s+')).first;
              }
            }
          } catch (e) {
            developer.log(
              'hydrate ride for rating failed: $e',
              name: 'WS',
              level: 800,
            );
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
            developer.log(
              'hydrate job for rating failed: $e',
              name: 'WS',
              level: 800,
            );
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
            ref.read(routerProvider).go(AppRoutes.jobDetailPath(bookingId));
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
  }

  // Wire BEFORE the first connect so the very first io.Socket also picks
  // up handlers; the hook then fires synchronously on every subsequent
  // re-create. Matches the provider-side pattern in
  // apps/provider/lib/src/core/providers/socket_provider.dart.
  socket.onAfterCreate(attachHandlers);
  socket.connect();
}

bool _isNoDriversCancellation({required String reason}) {
  return isNoDriversSocketCancellation(reason: reason);
}
