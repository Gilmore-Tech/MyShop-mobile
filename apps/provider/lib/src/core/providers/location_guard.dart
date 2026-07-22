import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'availability_controller.dart';
import 'app_lifecycle_provider.dart';
import 'provider_status_provider.dart';

typedef LocationPermissionReader = Future<LocationPermission> Function();
typedef LocationUnavailableReporter = Future<void> Function(
  LocationUnavailableReason reason,
);

final locationPermissionReaderProvider = Provider<LocationPermissionReader>(
  (_) => Geolocator.checkPermission,
);

final locationServiceStatusStreamProvider = Provider<Stream<ServiceStatus>>(
  (_) => Geolocator.getServiceStatusStream(),
);

final locationGuardPollIntervalProvider =
    Provider<Duration>((_) => const Duration(seconds: 15));

final locationUnavailableReporterProvider =
    Provider<LocationUnavailableReporter>((ref) {
  return ref.read(availabilityControllerProvider).reportLocationUnavailable;
});

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
  int guardGeneration = 0;
  int? permissionCheckGeneration;

  void stop() {
    guardGeneration += 1;
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
    final generation = ++guardGeneration;
    final reportUnavailable = ref.read(locationUnavailableReporterProvider);

    // 1. Service-enabled changes emit on this stream on both platforms.
    serviceSub = ref.read(locationServiceStatusStreamProvider).listen((status) {
      if (generation != guardGeneration) return;
      if (status == ServiceStatus.disabled) {
        debugPrint('[LocationGuard] services disabled — reporting loss');
        unawaited(
          reportUnavailable(LocationUnavailableReason.serviceDisabled),
        );
      }
    });

    // 2. Permission changes don't emit a stream, so poll. 15s cadence is
    // fast enough to catch a Settings revocation before the backend TTL
    // dispatches a job, without burning CPU.
    permissionPoll =
        Timer.periodic(ref.read(locationGuardPollIntervalProvider), (_) async {
      if (generation != guardGeneration ||
          permissionCheckGeneration == generation) {
        return;
      }
      permissionCheckGeneration = generation;
      try {
        final permission = await ref.read(locationPermissionReaderProvider)();
        if (generation != guardGeneration) return;
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          debugPrint(
            '[LocationGuard] location permission lost — reporting loss',
          );
          await reportUnavailable(LocationUnavailableReason.permissionLost);
          return;
        }

        final foregrounded = ref.read(appForegroundedProvider);
        if (!foregrounded && permission != LocationPermission.always) {
          debugPrint(
            '[LocationGuard] app backgrounded without Always '
            'permission — reporting loss',
          );
          await reportUnavailable(
            LocationUnavailableReason.backgroundPermissionLost,
          );
        }
      } catch (error) {
        debugPrint('[LocationGuard] permission check failed: $error');
      } finally {
        if (permissionCheckGeneration == generation) {
          permissionCheckGeneration = null;
        }
      }
    });
  });
});
