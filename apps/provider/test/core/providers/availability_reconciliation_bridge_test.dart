import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/core/providers/availability_reconciliation_bridge.dart';
import 'package:myshop_provider/src/core/providers/provider_online_intent.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _TestAuthController extends AuthController {
  _TestAuthController(AuthState initialState)
      : super(
          _MockAuthRepository(),
          tokenStorage: _MockTokenStorage(),
        ) {
    state = initialState;
  }
}

void main() {
  test(
    'authenticated bridge defers exact-role identity until after construction',
    () async {
      const user = AuthUser(
        id: 'auth-user-1',
        phone: '+233241234567',
        fullName: 'Driver One',
        role: AuthRole.driver,
        driverProfile: DriverProfile(
          id: 'driver-role-1',
          verificationStatus: 'approved',
          kycStatus: 'verified',
          policeCheckStatus: 'approved',
          onlineStatus: 'offline',
          serviceRadiusKm: 5,
          payoutPreference: 'standard',
          cancellationCount30d: 0,
          ghanaCardVerified: true,
          languagePref: 'en',
        ),
      );
      final controller = _TestAuthController(
        const AuthAuthenticated(user),
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((_) => controller),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(availabilityReconciliationBridgeProvider),
        returnsNormally,
      );
      expect(
        container.read(currentProviderOnlineIntentIdentityProvider),
        isNull,
      );

      await Future<void>.delayed(Duration.zero);

      final identity =
          container.read(currentProviderOnlineIntentIdentityProvider);
      expect(identity?.role, ProviderOnlineIntentRole.driver);
      expect(identity?.roleAccountId, 'driver-role-1');
    },
  );
}
