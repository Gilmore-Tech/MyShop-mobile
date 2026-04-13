import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/app/provider_app.dart';
import 'src/core/di/providers.dart';
import 'src/features/auth/providers/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ProviderApp(),
    ),
  );
}
