import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  test('bootstrap waits for authenticated side effects before publishing state',
      () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final persistence = Completer<void>();
    final session = _session('driver-1', role: 'driver', sid: 'session-1');
    final publishedIdentities = <AuthSessionIdentity?>[];
    final user = AuthUser(
      id: 'driver-1',
      phone: '+233241234567',
      fullName: 'Driver One',
      role: AuthRole.driver,
    );

    when(() => repository.bootstrap()).thenAnswer(
        (_) async => ProviderBootstrapReady(user, session.identity!));
    when(() => repository.refreshProfileQuiet()).thenAnswer((_) async => null);
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);

    final controller = AuthController(
      repository,
      tokenStorage: storage,
      onSessionIdentityChanged: publishedIdentities.add,
      onAuthenticated: (_, ProviderType? role) => persistence.future,
    );

    final bootstrap = controller.bootstrap();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, isA<AuthUnknown>());
    expect(publishedIdentities, isEmpty);

    persistence.complete();
    await bootstrap;

    expect(controller.state, isA<AuthAuthenticated>());
    expect(publishedIdentities, [session.identity]);
  });

  test('temporary bootstrap failure stays in non-OTP recovery', () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    when(() => repository.bootstrap()).thenAnswer(
      (_) async => const ProviderBootstrapDeferred(),
    );
    final controller = AuthController(
      repository,
      tokenStorage: storage,
    );

    await controller.bootstrap();

    expect(controller.state, isA<AuthSessionRestorePending>());
    expect(controller.state, isNot(isA<AuthUnauthenticated>()));
    expect(controller.state, isNot(isA<AuthOtpSent>()));
  });

  test('retry restores the same provider session without another OTP',
      () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final session = _session('driver-1', role: 'driver', sid: 'session-1');
    var attempts = 0;
    when(() => repository.bootstrap()).thenAnswer((_) async {
      attempts += 1;
      return attempts == 1
          ? const ProviderBootstrapDeferred()
          : ProviderBootstrapReady(_driver, session.identity!);
    });
    when(() => repository.refreshProfileQuiet()).thenAnswer((_) async => null);
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    final controller = AuthController(
      repository,
      tokenStorage: storage,
    );

    await controller.bootstrap();
    await controller.retrySessionRestore();

    expect(controller.state, isA<AuthAuthenticated>());
    verifyNever(() => repository.providerLogin(any()));
  });

  test('terminal server logout wins over a late provider bootstrap result',
      () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final result = Completer<ProviderBootstrapResult>();
    final session = _session('driver-1', role: 'driver', sid: 'session-1');
    when(() => repository.bootstrap()).thenAnswer((_) => result.future);
    final controller = AuthController(
      repository,
      tokenStorage: storage,
    );

    final bootstrap = controller.bootstrap();
    controller.onForceLogoutFromInterceptor();
    result.complete(ProviderBootstrapReady(_driver, session.identity!));
    await bootstrap;

    expect(controller.state, isA<AuthUnauthenticated>());
    expect(
      (controller.state as AuthUnauthenticated).error,
      contains('session ended'),
    );
  });

  test('app resume has no client-side authentication age logout', () {
    final source = File('lib/src/app/provider_app.dart').readAsStringSync();
    final resumeStart = source.indexOf('case AppLifecycleState.resumed:');
    final resumeEnd = source.indexOf(
      'case AppLifecycleState.paused:',
      resumeStart,
    );

    expect(resumeStart, greaterThanOrEqualTo(0));
    expect(resumeEnd, greaterThan(resumeStart));
    final resumeBody = source.substring(resumeStart, resumeEnd);
    expect(resumeBody, isNot(contains('authControllerProvider')));
    expect(resumeBody, isNot(contains('logout(')));
    expect(resumeBody, isNot(contains('SessionStartedAt')));
  });

  test('issued provider session plus profile failure never requests OTP again',
      () async {
    const phone = '+233241234567';
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final session = _session('driver-1', role: 'driver', sid: 'session-1');
    when(() => repository.providerLogin(phone)).thenAnswer((_) async {});
    when(
      () => repository.providerVerifyOtp(phone: phone, code: '123456'),
    ).thenAnswer(
      (_) async => const ProviderSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        role: 'driver',
      ),
    );
    when(
      () => repository.fetchProfile(activeRole: AuthRole.driver),
    ).thenThrow(
      const ServerException(
        message: 'temporarily unavailable',
        statusCode: 503,
      ),
    );
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    final controller = AuthController(
      repository,
      tokenStorage: storage,
    );

    await controller.checkPhoneAndLogin(phone: phone);
    await controller.verifyOtp('123456');

    expect(controller.state, isA<AuthSessionRestorePending>());
    expect(
      (controller.state as AuthSessionRestorePending).intendedRole,
      ProviderType.driver,
    );

    when(
      () => repository.bootstrap(activeRole: AuthRole.driver),
    ).thenAnswer(
      (_) async => ProviderBootstrapReady(_driver, session.identity!),
    );
    when(() => repository.refreshProfileQuiet()).thenAnswer((_) async => null);
    await controller.retrySessionRestore();

    expect(controller.state, isA<AuthAuthenticated>());
    verify(
      () => repository.providerVerifyOtp(phone: phone, code: '123456'),
    ).called(1);
    verify(() => repository.fetchProfile(activeRole: AuthRole.driver))
        .called(1);
  });

  test('same-principal replacement SID suppresses a late bootstrap result',
      () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final result = Completer<ProviderBootstrapResult>();
    final sessionA = _session('driver-1', role: 'driver', sid: 'session-A');
    final sessionB = _session('driver-1', role: 'driver', sid: 'session-B');
    var current = sessionA;
    var authenticatedCallbacks = 0;
    when(() => repository.bootstrap()).thenAnswer((_) => result.future);
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    final controller = AuthController(
      repository,
      tokenStorage: storage,
      onAuthenticated: (_, __) async => authenticatedCallbacks += 1,
    );

    final bootstrap = controller.bootstrap();
    result.complete(ProviderBootstrapReady(_driver, sessionA.identity!));
    current = sessionB;
    await bootstrap;

    expect(controller.state, isNot(isA<AuthAuthenticated>()));
    expect(authenticatedCallbacks, 0);
  });

  test('replacement during authenticated side effects suppresses A publish',
      () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final sessionA = _session('driver-1', role: 'driver', sid: 'session-A');
    final sessionB = _session('driver-2', role: 'driver', sid: 'session-B');
    final callbackStarted = Completer<void>();
    final releaseCallback = Completer<void>();
    final publishedIdentities = <AuthSessionIdentity?>[];
    var current = sessionA;
    when(() => repository.bootstrap()).thenAnswer(
      (_) async => ProviderBootstrapReady(_driver, sessionA.identity!),
    );
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    final controller = AuthController(
      repository,
      tokenStorage: storage,
      onSessionIdentityChanged: publishedIdentities.add,
      onAuthenticated: (_, __) async {
        callbackStarted.complete();
        await releaseCallback.future;
      },
    );

    final bootstrap = controller.bootstrap();
    await callbackStarted.future;
    current = sessionB;
    releaseCallback.complete();
    await bootstrap;

    expect(controller.state, isNot(isA<AuthAuthenticated>()));
    expect(publishedIdentities, isEmpty);
  });

  for (final serverResult in ['false', 'error']) {
    test(
        'explicit logout cleans captured owner when server cleanup $serverResult',
        () async {
      final repository = _MockAuthRepository();
      final storage = _MockTokenStorage();
      final sessionA = _session('driver-1', role: 'driver', sid: 'session-A');
      final cleanupOwners = <AuthSessionIdentity?>[];
      when(() => repository.bootstrap()).thenAnswer(
        (_) async => ProviderBootstrapReady(_driver, sessionA.identity!),
      );
      when(() => repository.refreshProfileQuiet())
          .thenAnswer((_) async => null);
      when(() => storage.readTokenSnapshot()).thenAnswer((_) async => sessionA);
      if (serverResult == 'false') {
        when(() => repository.logout()).thenAnswer((_) async => false);
      } else {
        when(() => repository.logout())
            .thenThrow(StateError('server cleanup failed'));
      }
      final controller = AuthController(
        repository,
        tokenStorage: storage,
        onLocalStateClear: (_, identity) async {
          cleanupOwners.add(identity);
        },
      );
      await controller.bootstrap();

      await controller.logout();

      expect(cleanupOwners, [sessionA.identity]);
      expect(controller.state, isA<AuthUnauthenticated>());
    });
  }

  test('paused A logout cannot clobber a bootstrapped B session', () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final sessionA = _session('driver-1', role: 'driver', sid: 'session-A');
    final sessionB = _session('driver-2', role: 'driver', sid: 'session-B');
    final logoutResult = Completer<bool>();
    var current = sessionA;
    var bootstrapCount = 0;
    when(() => repository.bootstrap()).thenAnswer((_) async {
      bootstrapCount += 1;
      return bootstrapCount == 1
          ? ProviderBootstrapReady(_driver, sessionA.identity!)
          : ProviderBootstrapReady(_driver2, sessionB.identity!);
    });
    when(() => repository.refreshProfileQuiet()).thenAnswer((_) async => null);
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(() => repository.logout()).thenAnswer((_) => logoutResult.future);
    final cleanupOwners = <AuthSessionIdentity?>[];
    final publishedIdentities = <AuthSessionIdentity?>[];
    final controller = AuthController(
      repository,
      tokenStorage: storage,
      onSessionIdentityChanged: publishedIdentities.add,
      onLocalStateClear: (_, identity) async {
        cleanupOwners.add(identity);
      },
    );
    await controller.bootstrap();

    final logout = controller.logout();
    await Future<void>.delayed(Duration.zero);
    current = sessionB;
    await controller.bootstrap();
    expect((controller.state as AuthAuthenticated).user.id, 'driver-2');

    logoutResult.complete(false);
    await logout;

    expect((controller.state as AuthAuthenticated).user.id, 'driver-2');
    expect(cleanupOwners, [sessionA.identity]);
    expect(
      publishedIdentities,
      [sessionA.identity, null, sessionB.identity],
    );
  });

  test('force logout passes its captured SID to local cleanup', () async {
    final repository = _MockAuthRepository();
    final storage = _MockTokenStorage();
    final sessionA = _session('driver-1', role: 'driver', sid: 'session-A');
    when(() => repository.bootstrap()).thenAnswer(
      (_) async => ProviderBootstrapReady(_driver, sessionA.identity!),
    );
    when(() => repository.refreshProfileQuiet()).thenAnswer((_) async => null);
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => sessionA);
    final cleanupOwners = <AuthSessionIdentity?>[];
    final controller = AuthController(
      repository,
      tokenStorage: storage,
      onLocalStateClear: (_, identity) async {
        cleanupOwners.add(identity);
      },
    );
    await controller.bootstrap();

    controller.onForceLogoutFromInterceptor(
      AuthForceLogoutEvent.fromSnapshot(sessionA),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cleanupOwners, [sessionA.identity]);
    expect(controller.state, isA<AuthUnauthenticated>());
  });
}

final _driver = AuthUser(
  id: 'driver-1',
  phone: '+233241234567',
  fullName: 'Driver One',
  role: AuthRole.driver,
);

final _driver2 = AuthUser(
  id: 'driver-2',
  phone: '+233241234568',
  fullName: 'Driver Two',
  role: AuthRole.driver,
);

AuthTokenSnapshot _session(
  String roleAccountId, {
  required String role,
  required String sid,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: 'auth-root-for-$roleAccountId',
        role: role,
        roleAccountId: roleAccountId,
        sid: sid,
        marker: 'access',
      ),
      refreshToken: _jwt(
        subject: 'auth-root-for-$roleAccountId',
        role: role,
        roleAccountId: roleAccountId,
        sid: sid,
        marker: 'refresh',
      ),
      storageFormat: AuthTokenStorageFormat.versioned,
    );

String _jwt({
  required String subject,
  required String role,
  required String roleAccountId,
  required String sid,
  required String marker,
}) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': subject,
            'role': role,
            'roleAccountId': roleAccountId,
            'sid': sid,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'e30.$payload.$marker';
}
