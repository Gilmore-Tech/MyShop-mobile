import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/provider_app.dart';
import 'src/features/profile/providers/provider_type_provider.dart';

/// Selects which provider role the app launches with.
///
/// Pass at run time:
///   flutter run --dart-define=ROLE=driver
///   flutter run --dart-define=ROLE=artisan
///
/// Defaults to artisan so the new artisan flow renders during development.
const _kRole = String.fromEnvironment('ROLE', defaultValue: 'artisan');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Initialize Firebase, secure storage, etc.
  runApp(
    ProviderScope(
      overrides: [
        providerTypeProvider.overrideWith(
          (ref) =>
              _kRole == 'driver' ? ProviderType.driver : ProviderType.artisan,
        ),
      ],
      child: const ProviderApp(),
    ),
  );
}
