import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'availability_controller.dart';
import 'app_lifecycle_provider.dart';
import 'provider_status_provider.dart';

/// Listens for location-service and permission changes while the provider
/// is online. If location becomes unusable (user disabled Location Services
/// in Settings, or revoked permission), flips the provider offline so the
/// UI doesn't lie about an online state that can't broadcast location.
///
/// Without this, a revoked-mid-session driver would show as online locally
/// and on the backend (until the location TTL kicks in), but emit no
/// location updates — invisible to the matcher and confusing to the user.
///
/// Watched once at app start so it stays alive across route changes.
final locationGuardProvider = Provider<void>((ref) {
  StreamSubscription<ServiceStatus>? serviceSub;
  Timer? permissionPoll;

  void stop() {
    serviceSub?.cancel();
    serviceSub = null;
    permissionPoll?.cancel();
    permissionPoll = null;
  }

  ref.onDispose(stop);

  ref.listen<DriverStatus>(providerStatusProvider, (_, next) {
    if (next.isOffline) {
      stop();
      return;
    }
    if (serviceSub != null) return;

    // 1. Service-enabled changes emit on this stream on both platforms.
    serviceSub = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled) {
        debugPrint('[LocationGuard] services disabled — forcing offline');
        ref
            .read(availabilityControllerProvider)
            .forceOfflineDueToLocationLost();
      }
    });

    // 2. Permission changes don't emit a stream, so poll. 15s cadence is
    // fast enough to catch a Settings revocation before the backend TTL
    // dispatches a job, without burning CPU.
    permissionPoll = Timer.periodic(const Duration(seconds: 15), (_) async {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint(
          '[LocationGuard] location permission lost — forcing offline',
        );
        await ref
            .read(availabilityControllerProvider)
            .forceOfflineDueToLocationLost();
        return;
      }

      final foregrounded = ref.read(appForegroundedProvider);
      if (!foregrounded && permission != LocationPermission.always) {
        debugPrint(
          '[LocationGuard] app backgrounded without Always '
          'permission — forcing offline',
        );
        await ref
            .read(availabilityControllerProvider)
            .forceOfflineDueToLocationLost();
      }
    });
  });
});
