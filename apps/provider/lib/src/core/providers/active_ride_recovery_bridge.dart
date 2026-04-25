import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/active_ride_persistence.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../di/providers.dart';

/// Recovers a stuck active ride after a crash, force-quit, or the
/// bounce-back bug that left the backend flagging the driver as `busy`
/// while the local UI had no idea there was an open ride.
///
/// Mechanics:
///   1. On every transition into [AuthAuthenticated] (initial bootstrap +
///      sign-in), read the persisted ride id (see [ActiveRidePersistence]).
///   2. GET /rides/:id to discover the current backend status.
///   3. If the ride is still active (accepted / driver_en_route / arrived /
///      in_progress), restore it into [activeRideProvider] so the home
///      shell renders the active-ride screen and the driver can complete
///      or cancel it. If it's already completed/cancelled, just clear the
///      persisted id so we don't keep retrying.
///
/// Watched once at app start (see main.dart) so it stays subscribed for
/// the container's lifetime.
final activeRideRecoveryBridgeProvider = Provider<void>((ref) {
  Future<void> tryRecover() async {
    final persistence = ActiveRidePersistence();
    final rideId = await persistence.read();
    if (rideId == null || rideId.isEmpty) return;

    debugPrint('[ActiveRideRecovery] checking persisted ride $rideId');
    try {
      final json = await ref.read(rideServiceProvider).getRide(rideId);
      final ride = Ride.fromJson(json);

      if (ride.status.isActive) {
        debugPrint('[ActiveRideRecovery] restoring active ride ${ride.id} '
            '(status=${ride.status})');
        ref.read(activeRideProvider.notifier).restore(ride);
      } else {
        debugPrint('[ActiveRideRecovery] ride ${ride.id} no longer active '
            '(status=${ride.status}) — clearing persisted id');
        await persistence.clear();
      }
    } on ApiException catch (e) {
      // 404 / 403 / NOT_YOUR_RIDE → the ride is unreachable from this
      // account (likely already cleaned up server-side). Drop the id so
      // the next session doesn't keep retrying.
      debugPrint('[ActiveRideRecovery] getRide failed (${e.statusCode}): '
          '${e.errorCode ?? e.message} — clearing persisted id');
      if (e.statusCode == 404 || e.statusCode == 403) {
        await persistence.clear();
      }
    } catch (e) {
      // Network glitches — leave the id in place so the next launch can
      // retry. We don't want a transient failure to discard a real
      // active ride.
      debugPrint('[ActiveRideRecovery] getRide crashed: $e');
    }
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
});
