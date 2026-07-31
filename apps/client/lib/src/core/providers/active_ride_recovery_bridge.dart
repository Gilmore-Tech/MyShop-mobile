import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../di/providers.dart';
import 'service_notice_provider.dart';
import 'socket_provider.dart';

/// Mirror of the driver-side `active_ride_recovery_bridge.dart`. Restores
/// a rider's in-flight ride after a force-quit / crash so they can keep
/// watching the driver instead of having the trip stranded as a row in
/// the activity list with no way to resume.
///
/// Mechanics:
///   1. Reconcile the in-memory ride ID, then the exact durable booking key,
///      then the authenticated recent-rides fallback for legacy installs.
///   2. Rejoin `client:track:ride` and hydrate the authoritative REST snapshot
///      through the same providers used by live socket delivery.
///   3. Retry transient failures and rerun after socket/readiness recovery.
///
/// Watched once at app start (see main.dart). `Provider<void>` keeps the
/// listener subscription alive for the container's lifetime.
final clientActiveRideRecoveryBridgeProvider = Provider<void>((ref) {
  Future<void>? recoveryInFlight;

  Future<void> tryRecover() async {
    debugPrint('[ClientActiveRideRecovery] checking for in-flight ride');
    const attempts = 3;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final rideService = ref.read(rideServiceProvider);
        var rideId = ref.read(activeRideIdProvider);

        // The unresolved booking key is the exact durable identity for a ride
        // that may still be matching. Resolve it before falling back to a
        // recent-list scan so an offline cancellation cannot be mistaken for
        // "no active ride" and silently route the rider home.
        if (rideId == null || rideId.isEmpty) {
          final store = ref.read(rideBookingAttemptStoreProvider);
          final attempt = await store.read();
          if (attempt != null) {
            final booking = await rideService.lookupBookingAttempt(
              attempt.bookingKey,
            );
            if (booking == null) {
              await store.clear(bookingKey: attempt.bookingKey);
            } else {
              rideId = booking['rideId']?.toString();
              if (rideId == null || rideId.isEmpty) {
                throw const FormatException(
                  'Booking attempt response omitted rideId',
                );
              }
            }
          }
        }

        // Legacy installs may have no booking-key envelope. Accepted and
        // in-progress rides remain recoverable from the authenticated list.
        if (rideId == null || rideId.isEmpty) {
          final list = await rideService.listRides(limit: 5);
          for (final raw in list) {
            if (raw is! Map<String, dynamic>) continue;
            try {
              final ride = Ride.fromJson(raw);
              if (ride.status.isActive) {
                rideId = ride.id;
                break;
              }
            } catch (_) {
              // Skip malformed rows — not fatal.
            }
          }
        }
        if (rideId == null || rideId.isEmpty) {
          debugPrint(
              '[ClientActiveRideRecovery] no in-flight ride (attempt $attempt)');
          return;
        }
        debugPrint('[ClientActiveRideRecovery] reconciling $rideId');

        ref.read(activeRideIdProvider.notifier).state = rideId;

        // Join the ride room first so any in-flight `ride:state` /
        // `driver:location` emits start landing while we hydrate.
        try {
          final socket = ref.read(socketServiceProvider);
          if (socket.isConnected) {
            socket.emit('client:track:ride', {'rideId': rideId});
          }
        } catch (_) {}

        // Then push the snapshot through the same hydrate path the
        // matching-loop fallback uses — keeps every derived provider
        // identical to the live-flow case.
        await _applyResumedRide(ref, rideId);
        return;
      } on ApiException catch (e) {
        debugPrint('[ClientActiveRideRecovery] reconciliation failed '
            '(attempt $attempt/$attempts, status ${e.statusCode}): '
            '${e.errorCode ?? e.message}');
        if (e.statusCode == 401 || e.statusCode == 403) return;
      } on TypeError catch (e) {
        // Parse error — retrying won't help. Bail.
        debugPrint('[ClientActiveRideRecovery] listRides parse failed: $e');
        return;
      } on FormatException catch (e) {
        debugPrint('[ClientActiveRideRecovery] listRides parse failed: $e');
        return;
      } catch (e) {
        debugPrint('[ClientActiveRideRecovery] listRides crashed '
            '(attempt $attempt/$attempts): $e');
      }
      if (attempt < attempts) {
        final backoff = Duration(seconds: 3 * attempt);
        debugPrint(
            '[ClientActiveRideRecovery] retrying in ${backoff.inSeconds}s');
        await Future<void>.delayed(backoff);
      }
    }
    debugPrint(
        '[ClientActiveRideRecovery] exhausted retries — leaving state alone');
  }

  void scheduleRecovery() {
    if (recoveryInFlight != null) return;
    recoveryInFlight = tryRecover().whenComplete(() {
      recoveryInFlight = null;
    });
  }

  ref.listen<ClientAuthState>(
    clientAuthControllerProvider,
    (prev, next) {
      if (next is! AuthAuthenticated) return;
      if (prev is AuthAuthenticated) return;
      scheduleRecovery();
    },
    fireImmediately: true,
  );

  // If the initial sweep lost to a Render cold-start (3 retries × backoff
  // can still fall short of a 30–60 s wake), the socket's eventual connect
  // is a strong signal the network is now usable. Re-run recovery once
  // when the socket flips to connected. Reconcile even when an in-memory ride
  // ID exists: it may have become terminal while the device was offline.
  ref.listen<bool>(socketConnectedProvider, (prev, next) {
    if (next != true) return;
    if (prev == true) return;
    final isAuthed =
        ref.read(clientAuthControllerProvider) is AuthAuthenticated;
    if (!isAuthed) return;
    debugPrint('[ClientActiveRideRecovery] socket connected — re-checking');
    scheduleRecovery();
  });

  // A successful readiness probe increments this epoch. It covers the case
  // where the app stayed foregrounded for the whole outage and therefore had
  // no lifecycle or socket edge to trigger reconciliation.
  ref.listen<int>(
    serviceNoticeProvider.select((state) => state.recoveryEpoch),
    (previous, next) {
      if (next == previous) return;
      if (ref.read(clientAuthControllerProvider) is! AuthAuthenticated) return;
      debugPrint('[ClientActiveRideRecovery] service recovered — re-checking');
      scheduleRecovery();
    },
  );
});

/// Re-uses the matching-loop's hydrate to populate `matchedDriverProvider`
/// + `bookingPhaseProvider` + `rideTrackingPhaseProvider` + the live
/// driver position. The hydrate function is private to `ride_provider.dart`,
/// so we re-fetch the ride here and call [hydrateActiveRideFromRest] —
/// the public re-entry point exposed for this bridge.
Future<void> _applyResumedRide(Ref ref, String rideId) async {
  await hydrateActiveRideFromRest(
    ref.read,
    ref.read(rideServiceProvider),
    rideId,
  );
}
