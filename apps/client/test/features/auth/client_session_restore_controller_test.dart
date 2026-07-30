import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';

class _MockClientAuthRepository extends Mock implements ClientAuthRepository {}

void main() {
  late _MockClientAuthRepository repository;

  setUp(() {
    repository = _MockClientAuthRepository();
  });

  test('temporary bootstrap failure stays in non-OTP recovery', () async {
    when(() => repository.bootstrap()).thenAnswer(
      (_) async => const ClientBootstrapDeferred(),
    );
    final controller = ClientAuthController(repository);

    await controller.bootstrap();

    expect(controller.state, isA<AuthSessionRestorePending>());
    expect(controller.state, isNot(isA<AuthUnauthenticated>()));
    expect(controller.state, isNot(isA<AuthOtpSent>()));
  });

  test('bounded bootstrap timeout stays in non-OTP recovery', () async {
    when(() => repository.bootstrap()).thenAnswer(
      (_) => Completer<ClientBootstrapResult>().future,
    );
    final controller = ClientAuthController(
      repository,
      null,
      const Duration(milliseconds: 10),
    );

    await controller.bootstrap();

    expect(controller.state, isA<AuthSessionRestorePending>());
    expect(controller.state, isNot(isA<AuthUnauthenticated>()));
  });

  test('retry opens the saved session without requesting OTP', () async {
    var attempts = 0;
    when(() => repository.bootstrap()).thenAnswer((_) async {
      attempts += 1;
      return attempts == 1
          ? const ClientBootstrapDeferred()
          : const ClientBootstrapReady(_profile, _identity);
    });
    when(() => repository.isSessionCurrent(_identity))
        .thenAnswer((_) async => true);
    when(() => repository.fetchProfile()).thenAnswer((_) async => _profile);
    final controller = ClientAuthController(repository);

    await controller.bootstrap();
    expect(controller.state, isA<AuthSessionRestorePending>());

    await controller.retrySessionRestore();
    expect(controller.state, isA<AuthAuthenticated>());
    verifyNever(
      () => repository.loginClient(
        any(),
        forceLogin: any(named: 'forceLogin'),
      ),
    );
    verifyNever(
      () => repository.resendOtp(
        phone: any(named: 'phone'),
        channel: any(named: 'channel'),
      ),
    );
  });

  test('terminal logout wins over a late successful bootstrap', () async {
    final result = Completer<ClientBootstrapResult>();
    when(() => repository.bootstrap()).thenAnswer((_) => result.future);
    final controller = ClientAuthController(repository);

    final bootstrap = controller.bootstrap();
    controller.onForceLogoutFromInterceptor();
    result.complete(const ClientBootstrapReady(_profile, _identity));
    await bootstrap;

    expect(controller.state, isA<AuthUnauthenticated>());
    expect(
      (controller.state as AuthUnauthenticated).error,
      contains('session ended'),
    );
  });

  test('accepted OTP plus temporary profile failure does not ask for OTP again',
      () async {
    const phone = '+233241234567';
    when(() => repository.loginClient(phone)).thenAnswer((_) async {});
    when(
      () => repository.verifyOtp(phone: phone, code: '123456'),
    ).thenAnswer(
      (_) async => const TokenResponse(
        accessToken: 'access',
        refreshToken: 'refresh',
      ),
    );
    when(() => repository.readSessionIdentity())
        .thenAnswer((_) async => _identity);
    when(() => repository.fetchProfile()).thenThrow(
      const ServerException(
        message: 'temporarily unavailable',
        statusCode: 503,
      ),
    );
    final controller = ClientAuthController(repository);

    await controller.submitPhone(phone: phone);
    await controller.verifyOtp('123456');

    expect(controller.state, isA<AuthSessionRestorePending>());
    expect(controller.state, isNot(isA<AuthOtpSent>()));
    verify(() => repository.verifyOtp(phone: phone, code: '123456')).called(1);
  });
}

const _profile = UserProfile(
  id: 'client-1',
  phone: '+233241234567',
  fullName: 'Client User',
  languagePref: 'en',
  status: 'active',
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-07-27T00:00:00.000Z',
  client: ClientProfile(
    id: 'client-1',
    ghanaCardVerified: false,
    kycStatus: 'not_started',
    languagePref: 'en',
  ),
);

const _identity = AuthSessionIdentity(
  subject: 'auth-root-1',
  role: 'client',
  roleAccountId: 'client-1',
  sessionId: 'session-1',
);
