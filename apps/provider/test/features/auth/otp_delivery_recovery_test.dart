import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockTokenStorage extends Mock implements TokenStorage {}

const _phone = '+233241234567';
const _legalAcceptances = <LegalAcceptanceSelection>[
  LegalAcceptanceSelection(
    slug: 'terms',
    documentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    version: '1.4.1',
  ),
  LegalAcceptanceSelection(
    slug: 'privacy',
    documentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    version: '1.4.1',
  ),
];

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RegisterRequest(
        phone: _phone,
        fullName: 'Fallback',
        type: 'driver',
        legalAcceptances: _legalAcceptances,
      ),
    );
  });

  test(
      'provider registration enters OTP state when delivery failed but code is active',
      () async {
    final repository = _MockAuthRepository();
    final controller = AuthController(
      repository,
      tokenStorage: _MockTokenStorage(),
    );
    when(() => repository.register(any())).thenThrow(
      const ServerException(
        message: 'provider detail',
        statusCode: 503,
        errorCode: 'OTP_DELIVERY_FAILED',
        details: {'channel': 'sms', 'otpActive': true},
      ),
    );

    await controller.registerAndSendOtp(
      phone: _phone,
      fullName: 'Kwame Mensah',
      type: 'driver',
      legalAcceptances: _legalAcceptances,
      role: ProviderType.driver,
      rideCategories: const ['standard'],
    );

    final state = controller.state;
    expect(state, isA<AuthOtpSent>());
    expect((state as AuthOtpSent).phone, _phone);
    expect(state.isNewUser, isTrue);
    expect(state.role, ProviderType.driver);
    expect(state.error, contains('code is still active'));
  });

  test(
      'canonical rate limit enters OTP state when the server says a code is active',
      () async {
    final repository = _MockAuthRepository();
    final controller = AuthController(
      repository,
      tokenStorage: _MockTokenStorage(),
    );
    when(() => repository.register(any())).thenThrow(
      const ApiException(
        message: 'Too many requests. Please try again later.',
        statusCode: 429,
        errorCode: 'RATE_LIMIT_EXCEEDED',
        details: {
          'otpActive': true,
          'supportReference': '15286d11-fceb-43e6-ac0e-41f96d9a1b77',
        },
      ),
    );

    await controller.registerAndSendOtp(
      phone: _phone,
      fullName: 'Kwame Mensah',
      type: 'driver',
      legalAcceptances: _legalAcceptances,
      role: ProviderType.driver,
      rideCategories: const ['standard'],
    );

    final state = controller.state;
    expect(state, isA<AuthOtpSent>());
    expect((state as AuthOtpSent).error, contains('code is still active'));
    expect(state.error, contains('use resend'));
    expect(state.error, isNot(contains('15286d11')));
  });

  test('provider registration preserves the retained-role support signal',
      () async {
    final repository = _MockAuthRepository();
    final controller = AuthController(
      repository,
      tokenStorage: _MockTokenStorage(),
    );
    when(() => repository.register(any())).thenThrow(
      const ConflictException(
        message: 'backend detail must not be shown',
        errorCode: AuthErrorCodes.roleAccountRetained,
      ),
    );

    await controller.registerAndSendOtp(
      phone: _phone,
      fullName: 'Kwame Mensah',
      type: 'driver',
      legalAcceptances: _legalAcceptances,
      role: ProviderType.driver,
      rideCategories: const ['standard'],
    );

    final state = controller.state;
    expect(state, isA<AuthUnauthenticated>());
    expect((state as AuthUnauthenticated).requiresRoleRecoverySupport, isTrue);
    expect(state.error, contains('cannot be registered again'));
    expect(state.error, isNot(contains('backend detail')));
  });

  test('provider login uniform acknowledgement still advances to OTP state',
      () async {
    final repository = _MockAuthRepository();
    final controller = AuthController(
      repository,
      tokenStorage: _MockTokenStorage(),
    );
    when(() => repository.providerLogin(_phone)).thenAnswer((_) async {});

    await controller.checkPhoneAndLogin(phone: _phone);

    final state = controller.state;
    expect(state, isA<AuthOtpSent>());
    expect((state as AuthOtpSent).phone, _phone);
    expect(state.isNewUser, isFalse);
    expect(state.role, isNull);
  });

  test('concurrent provider verify triggers issue only one repository request',
      () async {
    final repository = _MockAuthRepository();
    final controller = AuthController(
      repository,
      tokenStorage: _MockTokenStorage(),
    );
    when(() => repository.register(any())).thenAnswer((_) async {});
    await controller.registerAndSendOtp(
      phone: _phone,
      fullName: 'Kwame Mensah',
      type: 'driver',
      legalAcceptances: _legalAcceptances,
      role: ProviderType.driver,
      rideCategories: const ['standard'],
    );
    final pending = Completer<TokenResponse>();
    when(() => repository.verifyOtp(phone: _phone, code: '123456'))
        .thenAnswer((_) => pending.future);

    final first = controller.verifyOtp('123456');
    final second = controller.verifyOtp('123456');
    verify(() => repository.verifyOtp(phone: _phone, code: '123456')).called(1);

    pending.completeError(
      const ApiException(
        message: 'Incorrect code',
        statusCode: 401,
        errorCode: 'INVALID_OTP',
      ),
    );
    await Future.wait([first, second]);
    expect(controller.state, isA<AuthOtpSent>());
    expect((controller.state as AuthOtpSent).isVerifying, isFalse);
  });
}
