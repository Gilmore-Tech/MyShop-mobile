import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[main] PROVIDER app starting — FCM build marker v3');

  // Cap the in-memory image cache. Flutter's default is 100 MB / 1000
  // entries — a handful of full-resolution client-uploaded photos is
  // enough to blow past that AND iOS's ~300 MB jetsam threshold. Paired
  // with per-image `memCacheWidth`/`memCacheHeight` hints at the call
  // sites, this keeps bitmap memory bounded even across long sessions.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

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

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ProviderApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_finishStartup(container));
  });
}

Future<void> _finishStartup(ProviderContainer container) async {
  unawaited(_loadOnboardingPreferences(container));

  for (final activate in <void Function()>[
    () => container.read(logoutCleanupBridgeProvider),
    () => container.read(activeRideRecoveryBridgeProvider),
    () => container.read(locationGuardProvider),
  ]) {
    try {
      activate();
    } catch (e) {
      debugPrint('[main] startup bridge failed: $e');
    }
  }

  final firebaseReadyFuture = _initializeFirebase();
  final notificationsReadyFuture = _initializeLocalNotifications();
  final firebaseReady = await firebaseReadyFuture;
  await notificationsReadyFuture;

  if (firebaseReady) {
    try {
      container.read(firebaseReadyProvider.notifier).state = true;
      container.listen<void>(fcmAuthBridgeProvider, (_, __) {});
      unawaited(container.read(fcmServiceProvider).init().catchError(
            (Object e) => debugPrint('[main] FCM init failed: $e'),
          ));
    } catch (e) {
      debugPrint('[main] FCM bridge setup failed: $e');
    }
  }

  unawaited(_warmLocation(container));
}

Future<void> _loadOnboardingPreferences(ProviderContainer container) async {
  try {
    await loadOnboardingFlag(container).timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('[main] onboarding preferences unavailable: $e');
  } finally {
    container.read(onboardingFlagLoadedProvider.notifier).state = true;
  }
}

Future<bool> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
    return true;
  } catch (e) {
    debugPrint('[main] Firebase init failed — push disabled: $e');
    return false;
  }
}

Future<void> _initializeLocalNotifications() async {
  try {
    await LocalNotificationService.instance
        .init()
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('[main] Local notifications init failed: $e');
  }
}

Future<void> _warmLocation(ProviderContainer container) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        timeLimit: Duration(seconds: 10),
      ),
    );
    container.read(lastKnownPositionProvider.notifier).state = position;
  } catch (e) {
    debugPrint('[main] location warm-up failed: $e');
  }
}
