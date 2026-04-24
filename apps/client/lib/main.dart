import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'src/app/client_app.dart';
import 'src/core/constants/mapbox_config.dart';
import 'src/core/di/providers.dart';
import 'src/core/providers/socket_provider.dart';
import 'src/features/auth/providers/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MapboxOptions.setAccessToken(MapboxConfig.accessToken);

  // TODO: await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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

  // Activate the WebSocket connection provider so it reacts to auth state
  // changes. Connects automatically when the user logs in, disconnects on
  // logout. Incoming events push live updates into Riverpod providers.
  container.read(socketConnectionProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ClientApp(),
    ),
  );
}
