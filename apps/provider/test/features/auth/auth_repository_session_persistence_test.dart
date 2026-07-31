import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockDeviceIdProvider extends Mock implements DeviceIdProvider {}

class _FakeProviderSelectRoleRequest extends Fake
    implements ProviderSelectRoleRequest {}

class _FakeLoginRequest extends Fake implements LoginRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeProviderSelectRoleRequest());
    registerFallbackValue(_FakeLoginRequest());
    registerFallbackValue(const AuthTokenSnapshot.empty());
  });

  test('pre-auth phone stays attempt-scoped until a session is accepted',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final device = _MockDeviceIdProvider();
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: device,
    );
    when(() => device.ensureDeviceId()).thenAnswer((_) async => 'device-1');
    when(() => device.readDeviceInfo()).thenAnswer((_) async => 'test-device');
    when(() => service.providerLogin(any())).thenAnswer((_) async {});

    await repository.providerLogin('+233240000002');

    verifyNever(() => storage.writePhone(any()));
    verifyNever(() => storage.writeRole(any()));
  });

  test('selected provider session is durable before old cache cleanup',
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
    when(() => storage.clearCachedProfileIfCurrent(any()))
        .thenAnswer((_) async => true);
    when(
      () => storage.writeTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => storage.writeSessionMetadataIfCurrent(
        expected: any(named: 'expected'),
        phone: any(named: 'phone'),
        role: any(named: 'role'),
      ),
    ).thenAnswer((_) async => true);

    final result = await repository.providerSelectRole(
      selectionToken: 'selection-token',
      role: 'driver',
      phone: '+233241234567',
    );

    expect(result, same(session));
    verifyInOrder([
      () => storage.writeTokens(
            accessToken: 'access-token',
            refreshToken: 'refresh-token',
          ),
      () => storage.clearCachedProfileIfCurrent(any()),
      () => storage.writeSessionMetadataIfCurrent(
            expected: any(named: 'expected'),
            phone: '+233241234567',
            role: 'driver',
          ),
    ]);
  });

  test('cache cleanup failure cannot discard an accepted provider session',
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
    when(
      () => storage.writeTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.clearCachedProfileIfCurrent(any()))
        .thenThrow(StateError('temporary keychain error'));
    when(
      () => storage.writeSessionMetadataIfCurrent(
        expected: any(named: 'expected'),
        phone: any(named: 'phone'),
        role: any(named: 'role'),
      ),
    ).thenAnswer((_) async => true);

    final result = await repository.providerSelectRole(
      selectionToken: 'selection-token',
      role: 'driver',
      phone: '+233241234567',
    );

    expect(result, same(session));
    verify(
      () => storage.writeSessionMetadataIfCurrent(
        expected: any(named: 'expected'),
        phone: '+233241234567',
        role: 'driver',
      ),
    ).called(1);
  });

  test('late account A completion cannot overwrite account B metadata',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
    const sessionA = ProviderSession(
      accessToken: 'access-A',
      refreshToken: 'refresh-A',
      role: 'driver',
    );
    when(() => service.providerSelectRole(any()))
        .thenAnswer((_) async => sessionA);
    when(
      () => storage.writeTokens(
        accessToken: 'access-A',
        refreshToken: 'refresh-A',
      ),
    ).thenAnswer((_) async {});
    // false models account B replacing storage between A's durable token
    // write and A's late metadata/cache completion.
    when(() => storage.clearCachedProfileIfCurrent(any()))
        .thenAnswer((_) async => false);
    when(
      () => storage.writeSessionMetadataIfCurrent(
        expected: any(named: 'expected'),
        phone: any(named: 'phone'),
        role: any(named: 'role'),
      ),
    ).thenAnswer((_) async => false);

    await repository.providerSelectRole(
      selectionToken: 'selection-token-A',
      role: 'driver',
      phone: '+233240000001',
    );

    final expected = verify(
      () => storage.writeSessionMetadataIfCurrent(
        expected: captureAny(named: 'expected'),
        phone: '+233240000001',
        role: 'driver',
      ),
    ).captured.single as AuthTokenSnapshot;
    expect(expected.accessToken, 'access-A');
    expect(expected.refreshToken, 'refresh-A');
    verifyNever(() => storage.clearCachedProfile());
    verifyNever(() => storage.writeRole(any()));
    verifyNever(() => storage.writePhone(any()));
  });

  test('temporary profile failure preserves the provider session', () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final session = _session('1', role: 'driver');
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    when(() => storage.readCachedProfileJson()).thenAnswer((_) async => null);
    when(() => service.getMeWithRaw()).thenThrow(
      const ServerException(
        message: 'temporarily unavailable',
        statusCode: 503,
      ),
    );

    final result = await repository.bootstrap();

    expect(result, isA<ProviderBootstrapDeferred>());
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('an established provider session survives a later cold start', () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final session = _session('1', role: 'driver');
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    when(() => storage.readCachedProfileJson())
        .thenAnswer((_) async => jsonEncode(_driverProfileJson));

    final result = await repository.bootstrap();

    expect(result, isA<ProviderBootstrapReady>());
    expect(
      (result as ProviderBootstrapReady).user.role,
      AuthRole.driver,
    );
    verifyNever(() => storage.clearTokens());
  });

  test('an install with no provider token pair remains unauthenticated',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
    when(() => storage.readTokenSnapshot()).thenAnswer(
      (_) async => const AuthTokenSnapshot.empty(),
    );

    final result = await repository.bootstrap();

    expect(result, isA<ProviderBootstrapNoSession>());
    verifyNever(() => service.getMeWithRaw());
  });

  for (final fixture in [
    (name: 'current', exp: 4102444800),
    (name: 'expired', exp: 946684800),
  ]) {
    test('access-only provider ${fixture.name} state stays in recovery',
        () async {
      final service = _MockAuthService();
      final storage = _MockTokenStorage();
      final accessOnly = AuthTokenSnapshot(
        accessToken: _jwt(
          subject: 'auth-root-1',
          role: 'driver',
          roleAccountId: 'driver-1',
          sid: 'session-1',
          exp: fixture.exp,
          marker: 'access-only',
        ),
        refreshToken: null,
        storageFormat: AuthTokenStorageFormat.legacy,
      );
      final repository = AuthRepository(
        service: service,
        tokenStorage: storage,
        deviceIdProvider: _MockDeviceIdProvider(),
      );
      when(() => storage.readTokenSnapshot())
          .thenAnswer((_) async => accessOnly);

      final result = await repository.bootstrap();

      expect(result, isA<ProviderBootstrapDeferred>());
      expect(
        (result as ProviderBootstrapDeferred).cause,
        isA<AccessOnlyAuthSessionException>(),
      );
      verifyNever(() => storage.readCachedProfileJson());
      verifyNever(() => service.getMeWithRaw());
      verifyNever(() => storage.clearTokens());
      verifyNever(() => storage.clearAuthTokensOnly());
    });
  }

  test('a late provider profile cannot overwrite a replacement session cache',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final sessionA = _session('1', role: 'driver', sid: 'session-A');
    final sessionB = _session('2', role: 'driver', sid: 'session-B');
    var current = sessionA;
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
    final response =
        Completer<({UserProfile profile, Map<String, dynamic> raw})>();
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(() => service.getMeWithRaw()).thenAnswer((_) => response.future);
    when(
      () => storage.writeCachedProfileJsonIfCurrent(
        expectedIdentity: sessionA.identity!,
        json: any(named: 'json'),
      ),
    ).thenAnswer(
      (_) async => current.belongsTo(sessionA.identity!),
    );

    final fetch = repository.fetchProfile(activeRole: AuthRole.driver);
    await Future<void>.delayed(Duration.zero);
    current = sessionB;
    response.complete(
      (
        profile: UserProfile.fromJson(_driverProfileJson),
        raw: _driverProfileJson,
      ),
    );

    await expectLater(fetch, throwsA(isA<StaleAuthSessionException>()));
    verifyNever(() => storage.writeCachedProfileJson(any()));
  });

  test('refresh-only provider session is repaired before restore', () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final refreshOnly = _session(
      '1',
      role: 'driver',
      includeAccess: false,
    );
    final repaired = _session('1', role: 'driver');
    var current = refreshOnly;
    AuthTokenSnapshot? observed;
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
      refreshSession: (expected) async {
        observed = expected;
        current = repaired;
        return repaired.accessToken;
      },
    );
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(() => storage.readCachedProfileJson())
        .thenAnswer((_) async => jsonEncode(_driverProfileJson));

    final result = await repository.bootstrap();

    expect(observed, same(refreshOnly));
    expect(result, isA<ProviderBootstrapReady>());
  });

  for (final role in const ['driver', 'artisan']) {
    test('pre-SID $role refresh token upgrades through bootstrap recovery',
        () async {
      final service = _MockAuthService();
      final storage = _MockTokenStorage();
      final legacy = _legacyPair('1', role: role);
      final upgraded = _session('1', role: role);
      var current = legacy;
      AuthTokenSnapshot? observed;
      final repository = AuthRepository(
        service: service,
        tokenStorage: storage,
        deviceIdProvider: _MockDeviceIdProvider(),
        refreshSession: (expected) async {
          observed = expected;
          current = upgraded;
          return upgraded.accessToken;
        },
      );
      when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
      when(() => storage.readCachedProfileJson()).thenAnswer(
        (_) async => jsonEncode(
          role == 'driver' ? _driverProfileJson : _artisanProfileJson,
        ),
      );

      final result = await repository.bootstrap();

      expect(observed, same(legacy));
      expect(result, isA<ProviderBootstrapReady>());
      expect(
        (result as ProviderBootstrapReady).user.role.name,
        role,
      );
    });
  }

  for (final role in const ['driver', 'artisan']) {
    test('interrupted $role upgrade proves and retains its original SID',
        () async {
      final service = _MockAuthService();
      final storage = _MockTokenStorage();
      final interrupted = _interruptedUpgrade(
        '1',
        role: role,
        sid: 'session-1',
      );
      final upgraded = _session('1', role: role, sid: 'session-1');
      var current = interrupted;
      AuthTokenSnapshot? observed;
      final repository = AuthRepository(
        service: service,
        tokenStorage: storage,
        deviceIdProvider: _MockDeviceIdProvider(),
        refreshSession: (expected) async {
          observed = expected;
          current = upgraded;
          return upgraded.accessToken;
        },
      );
      when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
      when(() => storage.readCachedProfileJson()).thenAnswer(
        (_) async => jsonEncode(
          role == 'driver' ? _driverProfileJson : _artisanProfileJson,
        ),
      );

      final result = await repository.bootstrap();

      expect(observed, same(interrupted));
      expect(result, isA<ProviderBootstrapReady>());
      expect(
          current.identity?.generation, interrupted.accessLineage?.generation);
    });
  }

  test('interrupted provider upgrade rejects a returned replacement SID',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final interrupted = _interruptedUpgrade(
      '1',
      role: 'driver',
      sid: 'session-A',
    );
    final wrongSid = _session('1', role: 'driver', sid: 'session-B');
    var current = interrupted;
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
      refreshSession: (_) async {
        current = wrongSid;
        return wrongSid.accessToken;
      },
    );
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);

    final result = await repository.bootstrap();

    expect(result, isA<ProviderBootstrapDeferred>());
    verifyNever(() => storage.readCachedProfileJson());
  });

  test('logout revocation and local clear stay bound to the captured SID',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    var repairs = 0;
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
      refreshLogoutSession: (_) async {
        repairs += 1;
        return null;
      },
    );
    final sessionA = _session(
      '1',
      role: 'driver',
      sid: 'session-A',
      accessExp: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
    );
    final fence = AuthExplicitLogoutFence(id: 'logout-A', owner: sessionA);
    when(() => storage.beginExplicitLogout()).thenAnswer((_) async => fence);
    when(() => storage.readExplicitLogoutOwner(fence))
        .thenAnswer((_) async => sessionA);
    when(
      () => service.logout(
        expectedIdentity: sessionA.identity,
        explicitLogoutSession: sessionA,
      ),
    ).thenAnswer((_) async {});
    when(() => storage.finishExplicitLogout(fence))
        .thenAnswer((_) async => true);

    expect(await repository.logout(), isTrue);

    verify(
      () => service.logout(
        expectedIdentity: sessionA.identity,
        explicitLogoutSession: sessionA,
      ),
    ).called(1);
    verify(() => storage.finishExplicitLogout(fence)).called(1);
    verifyNever(() => storage.clearTokens());
    expect(repairs, 0);
  });

  test('full-SID logout repairs when access expiry cannot be proved', () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    var repairs = 0;
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
      refreshLogoutSession: (_) async {
        repairs += 1;
        return null;
      },
    );
    final sessionA = _session('1', role: 'driver', sid: 'session-A');
    final fence = AuthExplicitLogoutFence(
      id: 'logout-unknown-expiry-A',
      owner: sessionA,
    );
    when(() => storage.beginExplicitLogout()).thenAnswer((_) async => fence);
    when(() => storage.readExplicitLogoutOwner(fence))
        .thenAnswer((_) async => sessionA);
    when(
      () => service.logout(
        expectedIdentity: sessionA.identity,
        explicitLogoutSession: sessionA,
      ),
    ).thenAnswer((_) async {});
    when(() => storage.finishExplicitLogout(fence))
        .thenAnswer((_) async => true);

    expect(await repository.logout(), isTrue);

    expect(repairs, 1);
    verify(
      () => service.logout(
        expectedIdentity: sessionA.identity,
        explicitLogoutSession: sessionA,
      ),
    ).called(1);
    verify(() => storage.finishExplicitLogout(fence)).called(1);
  });

  test('full-SID logout refreshes behind the fence and revokes successor',
      () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final original = _session(
      '1',
      role: 'driver',
      sid: 'session-A',
      markerSuffix: '-old',
      accessExp: DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
    );
    final successor = _session(
      '1',
      role: 'driver',
      sid: 'session-A',
      markerSuffix: '-new',
      accessExp: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
    );
    final fence = AuthExplicitLogoutFence(
      id: 'logout-expired-A',
      owner: original,
    );
    AuthExplicitLogoutFence? repairedFence;
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
      refreshLogoutSession: (value) async {
        repairedFence = value;
        return successor;
      },
    );
    when(() => storage.beginExplicitLogout()).thenAnswer((_) async => fence);
    when(() => storage.readExplicitLogoutOwner(fence))
        .thenAnswer((_) async => original);
    when(
      () => service.logout(
        expectedIdentity: successor.identity,
        explicitLogoutSession: successor,
      ),
    ).thenAnswer((_) async {});
    when(() => storage.finishExplicitLogout(fence))
        .thenAnswer((_) async => true);

    expect(await repository.logout(), isTrue);

    expect(repairedFence, same(fence));
    verify(
      () => service.logout(
        expectedIdentity: successor.identity,
        explicitLogoutSession: successor,
      ),
    ).called(1);
    verify(() => storage.finishExplicitLogout(fence)).called(1);
    verifyNever(
      () => service.logout(
        expectedIdentity: original.identity,
        explicitLogoutSession: original,
      ),
    );
  });
}

AuthTokenSnapshot _session(
  String account, {
  required String role,
  String? sid,
  bool includeAccess = true,
  String markerSuffix = '',
  int? accessExp,
}) {
  final subject = 'auth-root-$account';
  final roleAccountId = '$role-$account';
  final sessionId = sid ?? 'session-$account';
  return AuthTokenSnapshot(
    accessToken: includeAccess
        ? _jwt(
            subject: subject,
            role: role,
            roleAccountId: roleAccountId,
            sid: sessionId,
            exp: accessExp,
            marker: 'access$markerSuffix',
          )
        : null,
    refreshToken: _jwt(
      subject: subject,
      role: role,
      roleAccountId: roleAccountId,
      sid: sessionId,
      marker: 'refresh$markerSuffix',
    ),
    storageFormat: AuthTokenStorageFormat.versioned,
  );
}

AuthTokenSnapshot _legacyPair(
  String account, {
  required String role,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        marker: 'legacy-access',
      ),
      refreshToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        marker: 'legacy-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.legacy,
    );

AuthTokenSnapshot _interruptedUpgrade(
  String account, {
  required String role,
  required String sid,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        sid: sid,
        includeRoleAccountId: false,
        marker: 'migrated-access',
      ),
      refreshToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        marker: 'legacy-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.legacy,
    );

String _jwt({
  required String subject,
  required String role,
  String? roleAccountId,
  String? sid,
  int? exp,
  bool includeRoleAccountId = true,
  required String marker,
}) {
  final claims = <String, dynamic>{'sub': subject, 'role': role};
  if (sid != null) claims['sid'] = sid;
  if (sid != null && includeRoleAccountId) {
    claims['roleAccountId'] = roleAccountId ?? '$role-account-for-$subject';
  }
  if (exp != null) claims['exp'] = exp;
  final payload =
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  return 'e30.$payload.$marker';
}

final Map<String, dynamic> _profileBase = {
  'id': 'user-1',
  'phone': '+233241234567',
  'fullName': 'Provider One',
  'languagePref': 'en',
  'status': 'active',
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-07-27T00:00:00.000Z',
};

final Map<String, dynamic> _driverProfileJson = {
  ..._profileBase,
  'driver': {
    'id': 'driver-1',
    'verificationStatus': 'approved',
  },
};

final Map<String, dynamic> _artisanProfileJson = {
  ..._profileBase,
  'artisan': {
    'id': 'artisan-1',
    'verificationStatus': 'approved',
    'businessName': 'Provider One Services',
  },
};
