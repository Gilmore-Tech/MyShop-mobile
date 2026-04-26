import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../di/providers.dart';
import 'socket_provider.dart';

/// Mirror of the driver-side `active_ride_recovery_bridge.dart`. Restores
/// a rider's in-flight ride after a force-quit / crash so they can keep
/// watching the driver instead of having the trip stranded as a row in
/// the activity list with no way to resume.
///
/// Mechanics:
///   1. On every transition into [AuthAuthenticated], fetch the rider's
///      recent rides and pick out anything whose status is still active
///      (`accepted | driver_en_route | arrived_at_pickup | in_progress`).
///   2. If found, set [activeRideIdProvider] and re-emit `client:track:ride`
///      so the rider rejoins the ride room. The same hydrate path the
///      matching loop uses populates [matchedDriverProvider] and the
///      tracking phase, which the [MainShell]'s router-listener uses to
///      navigate to the tracking screen.
///   3. Retries on transient network failures — Render free-tier cold
///      starts can eat 30–60 s on the first request after a long idle.
///
/// Watched once at app start (see main.dart). `Provider<void>` keeps the
/// listener subscription alive for the container's lifetime.
final clientActiveRideRecoveryBridgeProvider = Provider<void>((ref) {
  Future<void> tryRecover() async {
    debugPrint('[ClientActiveRideRecovery] checking for in-flight ride');
    const attempts = 3;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final rideService = ref.read(rideServiceProvider);
        // Backend doesn't have a `GET /clients/me/active-ride` yet (driver
        // got one as P1-1; client equivalent is on the punch list). Until
        // it does, list recent rides and filter — the rider only ever has
        // one ride active at a time so the most recent active row is it.
        final list = await rideService.listRides(limit: 5);
        Ride? active;
        for (final raw in list) {
          if (raw is! Map<String, dynamic>) continue;
          try {
            final ride = Ride.fromJson(raw);
            if (ride.status.isActive) {
              active = ride;
              break;
            }
          } catch (_) {
            // Skip malformed rows — not fatal.
          }
        }
        if (active == null) {
          debugPrint(
              '[ClientActiveRideRecovery] no in-flight ride (attempt $attempt)');
          return;
        }
        debugPrint('[ClientActiveRideRecovery] resuming ${active.id} '
            '(status=${active.status})');

        // Drive the same providers a fresh `ride:state` event would. We
        // already have the parsed ride entity, but we need the raw map
        // shape to share the snapshot pipeline (it reads top-level fare
        // breakdown fields the model doesn't expose). Re-fetch the full
        // entity by id and apply.
        ref.read(activeRideIdProvider.notifier).state = active.id;

        // Join the ride room first so any in-flight `ride:state` /
        // `driver:location` emits start landing while we hydrate.
        try {
          final socket = ref.read(socketServiceProvider);
          if (socket.isConnected) {
            socket.emit('client:track:ride', {'rideId': active.id});
          }
        } catch (_) {}

        // Then push the snapshot through the same hydrate path the
        // matching-loop fallback uses — keeps every derived provider
        // identical to the live-flow case.
        await _applyResumedRide(ref, active.id);
        return;
      } on ApiException catch (e) {
        debugPrint('[ClientActiveRideRecovery] listRides failed '
            '(attempt $attempt/$attempts, status ${e.statusCode}): '
            '${e.errorCode ?? e.message}');
        if (e.statusCode == 401 || e.statusCode == 403) return;
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

  ref.listen<ClientAuthState>(
    clientAuthControllerProvider,
    (prev, next) {
      if (next is! AuthAuthenticated) return;
      if (prev is AuthAuthenticated) return;
      tryRecover();
    },
    fireImmediately: true,
  );

  // If the initial sweep lost to a Render cold-start (3 retries × backoff
  // can still fall short of a 30–60 s wake), the socket's eventual connect
  // is a strong signal the network is now usable. Re-run recovery once
  // when the socket flips to connected and we have no active ride yet.
  ref.listen<bool>(socketConnectedProvider, (prev, next) {
    if (next != true) return;
    if (prev == true) return;
    final hasActiveRide = ref.read(activeRideIdProvider) != null;
    final isAuthed =
        ref.read(clientAuthControllerProvider) is AuthAuthenticated;
    if (hasActiveRide || !isAuthed) return;
    debugPrint('[ClientActiveRideRecovery] socket connected — re-checking');
    tryRecover();
  });
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
