import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/app/provider_app.dart';
import 'src/core/di/providers.dart';
import 'src/core/services/fcm_service.dart';
import 'src/core/services/local_notification_service.dart';
import 'src/features/auth/providers/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
}
