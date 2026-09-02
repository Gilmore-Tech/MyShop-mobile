import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/auth/screens/otp_verification_screen.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/registration/providers/registration_controller.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _ControlledOtpController extends AuthController {
  _ControlledOtpController({
    required this.authenticate,
    this.initialErrorCode,
  }) : super(
          _MockAuthRepository(),
          tokenStorage: _MockTokenStorage(),
        ) {
    state = AuthOtpSent(
      phone: '+233241234567',
      isNewUser: true,
      role: ProviderType.driver,
      error: initialErrorCode == null
          ? null
          : 'A referral is already linked to this account.',
      errorCode: initialErrorCode,
    );
  }

  final bool authenticate;
  final String? initialErrorCode;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> verifyOtp(String code) async {
    state = authenticate
        ? const AuthAuthenticated(
            AuthUser(
              id: 'driver-1',
              phone: '+233241234567',
              fullName: 'Kofi Mensah',
              role: AuthRole.driver,
            ),
          )
        : const AuthOtpSent(
            phone: '+233241234567',
            isNewUser: true,
            role: ProviderType.driver,
            error: 'Enter the correct verification code.',
          );
  }
}

void main() {
  Future<ProviderContainer> pumpOtp(
    WidgetTester tester, {
    required bool authenticate,
    String? initialErrorCode,
    String referralCode = '',
  }) async {
    final controller = _ControlledOtpController(
      authenticate: authenticate,
      initialErrorCode: initialErrorCode,
    );
    final draft = DriverRegistrationController()
      ..update(
        DriverRegistrationDraft(
          fullName: 'Kofi Mensah',
          vehicleMake: 'Toyota',
          vehicleModel: 'Corolla',
          vehicleYear: '2020',
          vehiclePlate: 'GR 1234-20',
          vehicleColor: 'Black',
          rideCategories: const ['regular'],
          referralCode: referralCode,
        ),
      );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((_) => controller),
        otpChannelsProvider.overrideWith((_) async => const []),
        driverRegistrationProvider.overrideWith((_) => draft),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProviderOtpVerificationScreen()),
      ),
    );
    return container;
  }

  testWidgets('failed OTP keeps the provider registration draft',
      (tester) async {
    final container = await pumpOtp(tester, authenticate: false);
    addTearDown(container.dispose);

    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pump();
    await tester.pump();

    expect(
      container.read(driverRegistrationProvider).fullName,
      'Kofi Mensah',
    );
    expect(container.read(authControllerProvider), isA<AuthOtpSent>());
  });

  testWidgets('authenticated OTP clears the completed provider draft',
      (tester) async {
    final container = await pumpOtp(tester, authenticate: true);
    addTearDown(container.dispose);

    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pump();
    await tester.pump();

    expect(container.read(driverRegistrationProvider).fullName, isEmpty);
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  testWidgets('attribution conflict offers removal and restarts registration',
      (tester) async {
    final container = await pumpOtp(
      tester,
      authenticate: false,
      initialErrorCode: 'SIGNUP_ATTRIBUTION_ALREADY_LINKED',
      referralCode: 'MYSHOP-ABC123',
    );
    addTearDown(container.dispose);

    await tester.tap(find.text('Remove code and request a new OTP'));
    await tester.pump();

    expect(container.read(driverRegistrationProvider).referralCode, isEmpty);
    expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
  });
}
