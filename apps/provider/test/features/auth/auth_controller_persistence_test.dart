import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  test('bootstrap does not publish authenticated state before role persistence',
      () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final persistence = Completer<void>();
    final user = AuthUser(
      id: 'user-1',
      phone: '+233241234567',
      fullName: 'Driver One',
      role: AuthRole.driver,
    );

    when(() => repository.bootstrap()).thenAnswer((_) async => user);
    when(() => storage.readRole()).thenAnswer((_) async => 'driver');
    when(() => repository.refreshProfileQuiet()).thenAnswer((_) async => null);

    final controller = AuthController(
      repository,
      tokenStorage: storage,
      onAuthenticated: (_, ProviderType? role) => persistence.future,
    );

    final bootstrap = controller.bootstrap();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, isA<AuthUnknown>());

    persistence.complete();
    await bootstrap;

    expect(controller.state, isA<AuthAuthenticated>());
  });
}
