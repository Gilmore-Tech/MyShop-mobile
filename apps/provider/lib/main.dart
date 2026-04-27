import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'firebase_options.dart';
import 'src/app/provider_app.dart';
import 'src/core/di/providers.dart';
import 'src/core/providers/active_ride_recovery_bridge.dart';
import 'src/core/providers/availability_controller.dart';
import 'src/core/providers/location_guard.dart';
import 'src/core/providers/logout_cleanup_bridge.dart';
import 'src/core/services/fcm_service.dart';
import 'src/core/services/local_notification_service.dart';
import 'src/features/auth/providers/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
//CE27-04A6
  // Cap the in-memory image cache. Flutter's default is 100 MB / 1000
  // entries — a handful of full-resolution client-uploaded photos is
  // enough to blow past that AND iOS's ~300 MB jetsam threshold. Paired
  // with per-image `memCacheWidth`/`memCacheHeight` hints at the call
  // sites, this keeps bitmap memory bounded even across long sessions.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[main] Firebase init failed: $e');
  }

  // Local notifications are cheap to init — safe to await. Guard in case
  // the platform channel isn't ready (simulator quirk).
  try {
    await LocalNotificationService.instance.init();
  } catch (e) {
    debugPrint('[main] Local notifications init failed: $e');
  }

  final container = ProviderContainer(
    overrides: [
      // Wire real backend services
      authServiceProvider.overrideWith(
        (ref) => ref.watch(realAuthServiceProvider),
      ),
      tokenStorageProvider.overrideWith(
        (ref) => ref.watch(appTokenStorageProvider),
      ),
    ],
  );

  // Eagerly load the onboarding flag so the router can read it synchronously.
  await loadOnboardingFlag(container);

  // Activate the auth-bridge so the FCM token is registered with the
  // backend once the user signs in. Safe to fire pre-runApp — it's just
  // a Riverpod watch, not an async op.
  container.read(fcmAuthBridgeProvider);

  // Activate the logout-cleanup bridge so the socket, surfaced-jobs
  // set, and online status are torn down whenever the user logs out.
  container.read(logoutCleanupBridgeProvider);

  // Recover any ride the driver was on when the app last died — without
  // this, a crash mid-ride leaves the backend flagging them `busy` and
  // the matcher excludes them on subsequent ride requests.
  container.read(activeRideRecoveryBridgeProvider);

  // Activate the location guard so we force the provider offline if
  // Location Services is disabled or permission is revoked while online.
  container.read(locationGuardProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ProviderApp(),
    ),
  );

  // Fire-and-forget: FCM init pulls the token, requests permissions, and
  // registers handlers. Running it AFTER runApp means any iOS permission
  // dialog / getInitialMessage round-trip never blocks the first frame.
  Future<void>(() async {
    try {
      await container.read(fcmServiceProvider).init();
    } catch (e) {
      debugPrint('[main] FCM init failed: $e');
    }
  });

  // Warm up the device GPS fix so the driver/artisan home maps and the
  // edit-business-info screen can centre on the user's actual position
  // rather than the pilot-city default. Fire-and-forget — failures
  // (denied permission, services off) just leave the cache empty and
  // callers fall back gracefully.
  Future<void>(() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      container.read(lastKnownPositionProvider.notifier).state = position;
    } catch (e) {
      debugPrint('[main] location warm-up failed: $e');
    }
  });
}
