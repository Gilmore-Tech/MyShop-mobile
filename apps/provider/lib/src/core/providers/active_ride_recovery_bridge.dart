import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../di/providers.dart';
import 'socket_provider.dart';

/// Recovers a stuck active ride after a crash, force-quit, or the
/// bounce-back bug that left the backend flagging the driver as `busy`
/// while the local UI had no idea there was an open ride.
///
/// Mechanics:
///   1. On every transition into [AuthAuthenticated] (initial bootstrap +
///      sign-in), call `GET /drivers/me/active-ride`.
///   2. If the server returns a ride entity, restore it into
///      [activeRideProvider] so the home shell renders the active-ride
///      screen and the driver can complete or cancel it.
///   3. If the server returns null (no active ride), do nothing — the
///      home shell stays on its normal view.
///
/// Replaces the previous SharedPreferences-based recovery: the server is
/// authoritative, the lookup survives reinstalls and device changes, and
/// there's no local-state drift to reconcile when the backend cleans up
/// a ride out from under us.
///
/// Watched once at app start (see main.dart) so it stays subscribed for
/// the container's lifetime.
final activeRideRecoveryBridgeProvider = Provider<void>((ref) {
  // Render free-tier cold starts can take 30–60 s; the first call after a
  // long idle period often times out. Retry a few times with backoff so a
  // freshly-launched app actually finds a real active ride instead of
  // silently giving up on a transient network blip.
  Future<void> tryRecover() async {
    debugPrint('[ActiveRideRecovery] checking server for active ride');
    const attempts = 3;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final json = await ref.read(rideServiceProvider).getMyActiveRide();
        if (json == null) {
          debugPrint('[ActiveRideRecovery] no active ride (attempt $attempt)');
          return;
        }
        final ride = Ride.fromJson(json);
        if (!ride.status.isActive) {
          debugPrint('[ActiveRideRecovery] ride ${ride.id} returned with '
              'non-active status (${ride.status}) — ignoring');
          return;
        }
        debugPrint('[ActiveRideRecovery] restoring active ride ${ride.id} '
            '(status=${ride.status})');
        ref.read(activeRideProvider.notifier).restore(ride);
        return;
      } on ApiException catch (e) {
        debugPrint('[ActiveRideRecovery] getMyActiveRide failed '
            '(attempt $attempt/$attempts, status ${e.statusCode}): '
            '${e.errorCode ?? e.message}');
        // Hard auth failures aren't transient — bail.
        if (e.statusCode == 401 || e.statusCode == 403) return;
      } catch (e) {
        debugPrint('[ActiveRideRecovery] getMyActiveRide crashed '
            '(attempt $attempt/$attempts): $e');
      }
      if (attempt < attempts) {
        final backoff = Duration(seconds: 3 * attempt);
        debugPrint('[ActiveRideRecovery] retrying in ${backoff.inSeconds}s');
        await Future<void>.delayed(backoff);
      }
    }
    debugPrint('[ActiveRideRecovery] exhausted retries — leaving state alone');
  }

  ref.listen<AuthState>(
    authControllerProvider,
    (prev, next) {
      if (next is! AuthAuthenticated) return;
      // Only fire on the transition INTO authenticated, not every rebuild.
      if (prev is AuthAuthenticated) return;
      tryRecover();
    },
    fireImmediately: true,
  );

  // Render free-tier cold starts can outlast our 3-retry window. If the
  // initial recovery exhausted before the backend woke up, the socket
  // coming online is a strong signal the network is now usable — try
  // recovery once more then. Only fires when we have no active ride yet,
  // to avoid stomping on a freshly-restored one.
  ref.listen<bool>(socketConnectedProvider, (prev, next) {
    if (next != true) return;
    if (prev == true) return;
    final hasActiveRide = ref.read(activeRideProvider).ride != null;
    final isAuthed =
        ref.read(authControllerProvider) is AuthAuthenticated;
    if (hasActiveRide || !isAuthed) return;
    debugPrint('[ActiveRideRecovery] socket connected — re-checking');
    tryRecover();
  });
});
