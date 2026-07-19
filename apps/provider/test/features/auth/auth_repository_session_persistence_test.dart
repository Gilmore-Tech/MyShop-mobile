import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockDeviceIdProvider extends Mock implements DeviceIdProvider {}

class _FakeProviderSelectRoleRequest extends Fake
    implements ProviderSelectRoleRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeProviderSelectRoleRequest());
  });

  test('selected provider role is persisted with the authenticated session',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
    const session = ProviderSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      role: 'driver',
    );

    when(() => service.providerSelectRole(any()))
        .thenAnswer((_) async => session);
    when(() => storage.readPhone()).thenAnswer((_) async => '+233241234567');
    when(
      () => storage.writeTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.writeRole(any())).thenAnswer((_) async {});
    when(() => storage.writePhone(any())).thenAnswer((_) async {});
    when(() => storage.writeSessionStartedAt(any())).thenAnswer((_) async {});

    final result = await repository.providerSelectRole(
      selectionToken: 'selection-token',
      role: 'driver',
    );

    expect(result, same(session));
    verifyInOrder([
      () => storage.writeTokens(
            accessToken: 'access-token',
            refreshToken: 'refresh-token',
          ),
      () => storage.writeRole('driver'),
      () => storage.writePhone('+233241234567'),
      () => storage.writeSessionStartedAt(any()),
    ]);
  });
}
