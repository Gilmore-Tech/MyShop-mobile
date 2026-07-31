import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockDeviceIdProvider extends Mock implements DeviceIdProvider {}

class _FakeVerifyOtpRequest extends Fake implements VerifyOtpRequest {}

class _FakeLoginRequest extends Fake implements LoginRequest {}

void main() {
  late _MockAuthService service;
  late _MockTokenStorage storage;
  late ClientAuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeVerifyOtpRequest());
    registerFallbackValue(_FakeLoginRequest());
    registerFallbackValue(const AuthTokenSnapshot.empty());
  });

  setUp(() {
    service = _MockAuthService();
    storage = _MockTokenStorage();
    repository = ClientAuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
  });

  test('pre-auth phone stays attempt-scoped until a session is accepted',
      () async {
    final device = _MockDeviceIdProvider();
    repository = ClientAuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: device,
    );
    when(() => device.ensureDeviceId()).thenAnswer((_) async => 'device-1');
    when(() => device.readDeviceInfo()).thenAnswer((_) async => 'test-device');
    when(() => service.loginClient(any())).thenAnswer((_) async {});

    await repository.loginClient('+233240000002');

    verifyNever(() => storage.writePhone(any()));
    verifyNever(() => storage.writeRole(any()));
  });

  test('restores a cached client profile without requesting another OTP',
      () async {
    final session = _session('1', role: 'client');
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    when(() => storage.readCachedProfileJson())
        .thenAnswer((_) async => jsonEncode(_profileJson));

    final result = await repository.bootstrap();

    expect(result, isA<ClientBootstrapReady>());
    final restored = (result as ClientBootstrapReady).profile;
    expect(restored.id, 'auth-root-1');
    expect(restored.client?.id, 'client-1');
    verifyNever(() => service.getMe());
    verifyNever(() => service.getMeWithRaw());
    verifyNever(() => storage.clearTokens());
  });

  test('distinguishes an install with no stored session', () async {
    when(() => storage.readTokenSnapshot()).thenAnswer(
      (_) async => const AuthTokenSnapshot.empty(),
    );

    final result = await repository.bootstrap();

    expect(result, isA<ClientBootstrapNoSession>());
    verifyNever(() => service.getMeWithRaw());
    verifyNever(() => storage.clearTokens());
  });

  for (final fixture in [
    (name: 'current', exp: 4102444800),
    (name: 'expired', exp: 946684800),
  ]) {
    test('access-only ${fixture.name} state stays in explicit recovery',
        () async {
      final accessOnly = AuthTokenSnapshot(
        accessToken: _jwt(
          subject: 'auth-root-1',
          role: 'client',
          roleAccountId: 'client-1',
          sid: 'session-1',
          exp: fixture.exp,
          marker: 'access-only',
        ),
        refreshToken: null,
        storageFormat: AuthTokenStorageFormat.legacy,
      );
      when(() => storage.readTokenSnapshot())
          .thenAnswer((_) async => accessOnly);

      final result = await repository.bootstrap();

      expect(result, isA<ClientBootstrapDeferred>());
      expect(
        (result as ClientBootstrapDeferred).cause,
        isA<AccessOnlyAuthSessionException>(),
      );
      verifyNever(() => storage.readCachedProfileJson());
      verifyNever(() => service.getMeWithRaw());
      verifyNever(() => storage.clearTokens());
      verifyNever(() => storage.clearAuthTokensOnly());
    });
  }

  test('keeps a stored session when its profile is temporarily unavailable',
      () async {
    final session = _session('1', role: 'client');
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    when(() => storage.readCachedProfileJson()).thenAnswer((_) async => null);
    when(() => service.getMeWithRaw()).thenThrow(
      const ServerException(
        message: 'temporarily unavailable',
        statusCode: 503,
      ),
    );

    final result = await repository.bootstrap();

    expect(result, isA<ClientBootstrapDeferred>());
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('keeps a stored session when a corrupt cache cannot be refreshed',
      () async {
    final session = _session('1', role: 'client');
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    when(() => storage.readCachedProfileJson())
        .thenAnswer((_) async => '{not-json');
    when(() => service.getMeWithRaw()).thenThrow(
      const ServerException(
        message: 'temporarily unavailable',
        statusCode: 503,
      ),
    );

    final result = await repository.bootstrap();

    expect(result, isA<ClientBootstrapDeferred>());
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('successful profile reads refresh the matching session cache', () async {
    final session = _session('1', role: 'client');
    final profile = UserProfile.fromJson(_profileJson);
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => session);
    when(() => service.getMeWithRaw()).thenAnswer(
      (_) async => (profile: profile, raw: _profileJson),
    );
    when(
      () => storage.writeCachedProfileJsonIfCurrent(
        expectedIdentity: session.identity!,
        json: any(named: 'json'),
      ),
    ).thenAnswer((_) async => true);

    final result = await repository.fetchProfile();

    expect(result.id, 'auth-root-1');
    final captured = verify(
      () => storage.writeCachedProfileJsonIfCurrent(
        expectedIdentity: session.identity!,
        json: captureAny(named: 'json'),
      ),
    ).captured;
    expect(jsonDecode(captured.single as String), _profileJson);
  });

  test('fresh OTP publishes tokens before removing the previous cache',
      () async {
    when(() => service.verifyOtp(any())).thenAnswer(
      (_) async => const TokenResponse(
        accessToken: 'access-B',
        refreshToken: 'refresh-B',
      ),
    );
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

    await repository.verifyOtp(
      phone: '+233241234567',
      code: '123456',
    );

    verifyInOrder([
      () => storage.writeTokens(
            accessToken: 'access-B',
            refreshToken: 'refresh-B',
          ),
      () => storage.clearCachedProfileIfCurrent(any()),
      () => storage.writeSessionMetadataIfCurrent(
            expected: any(named: 'expected'),
            phone: '+233241234567',
            role: 'client',
          ),
    ]);
  });

  test('cache cleanup failure cannot discard an accepted OTP session',
      () async {
    const accepted = TokenResponse(
      accessToken: 'access-B',
      refreshToken: 'refresh-B',
    );
    when(() => service.verifyOtp(any())).thenAnswer((_) async => accepted);
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

    final result = await repository.verifyOtp(
      phone: '+233241234567',
      code: '123456',
    );

    expect(result, same(accepted));
    verify(
      () => storage.writeTokens(
        accessToken: 'access-B',
        refreshToken: 'refresh-B',
      ),
    ).called(1);
    verify(
      () => storage.writeSessionMetadataIfCurrent(
        expected: any(named: 'expected'),
        phone: '+233241234567',
        role: 'client',
      ),
    ).called(1);
  });

  test('a late profile response cannot overwrite a replacement session cache',
      () async {
    final sessionA = _session('1', role: 'client', sid: 'session-A');
    final sessionB = _session('2', role: 'client', sid: 'session-B');
    var current = sessionA;
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

    final fetch = repository.fetchProfile();
    await Future<void>.delayed(Duration.zero);
    current = sessionB;
    response.complete(
      (profile: UserProfile.fromJson(_profileJson), raw: _profileJson),
    );

    await expectLater(fetch, throwsA(isA<StaleAuthSessionException>()));
    verifyNever(() => storage.writeCachedProfileJson(any()));
  });

  test('refresh-only current session is repaired before client restore',
      () async {
    final refreshOnly = _session(
      '1',
      role: 'client',
      includeAccess: false,
    );
    final repaired = _session('1', role: 'client');
    var current = refreshOnly;
    AuthTokenSnapshot? observed;
    final recoveringRepository = ClientAuthRepository(
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
        .thenAnswer((_) async => jsonEncode(_profileJson));

    final result = await recoveringRepository.bootstrap();

    expect(observed, same(refreshOnly));
    expect(result, isA<ClientBootstrapReady>());
  });

  test('pre-SID client refresh token upgrades through bootstrap recovery',
      () async {
    final legacy = _legacyPair('1', role: 'client');
    final upgraded = _session('1', role: 'client');
    var current = legacy;
    AuthTokenSnapshot? observed;
    final recoveringRepository = ClientAuthRepository(
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
    when(() => storage.readCachedProfileJson())
        .thenAnswer((_) async => jsonEncode(_profileJson));

    final result = await recoveringRepository.bootstrap();

    expect(observed, same(legacy));
    expect(result, isA<ClientBootstrapReady>());
    expect(
      (result as ClientBootstrapReady).profile.client?.id,
      upgraded.identity!.roleAccountId,
    );
  });

  test('interrupted client pre-SID upgrade keeps and proves its original SID',
      () async {
    final interrupted = _interruptedUpgrade(
      '1',
      role: 'client',
      sid: 'session-1',
    );
    final upgraded = _session('1', role: 'client', sid: 'session-1');
    var current = interrupted;
    AuthTokenSnapshot? observed;
    final recoveringRepository = ClientAuthRepository(
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
    when(() => storage.readCachedProfileJson())
        .thenAnswer((_) async => jsonEncode(_profileJson));

    final result = await recoveringRepository.bootstrap();

    expect(observed, same(interrupted));
    expect(result, isA<ClientBootstrapReady>());
    expect(current.identity?.generation, interrupted.accessLineage?.generation);
  });

  test('interrupted client upgrade rejects a returned replacement SID',
      () async {
    final interrupted = _interruptedUpgrade(
      '1',
      role: 'client',
      sid: 'session-A',
    );
    final wrongSid = _session('1', role: 'client', sid: 'session-B');
    var current = interrupted;
    final recoveringRepository = ClientAuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
      refreshSession: (_) async {
        current = wrongSid;
        return wrongSid.accessToken;
      },
    );
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);

    final result = await recoveringRepository.bootstrap();

    expect(result, isA<ClientBootstrapDeferred>());
    verifyNever(() => storage.readCachedProfileJson());
  });

  test(
      'provably valid logout skips repair and network failure still finishes '
      'the fence', () async {
    var repairs = 0;
    repository = ClientAuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
      refreshLogoutSession: (_) async {
        repairs += 1;
        return null;
      },
    );
    final session = _session(
      '1',
      role: 'client',
      sid: 'session-A',
      accessExp: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 15))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
    );
    final fence = AuthExplicitLogoutFence(
      id: 'logout-valid-A',
      owner: session,
    );
    when(() => storage.beginExplicitLogout()).thenAnswer((_) async => fence);
    when(() => storage.readExplicitLogoutOwner(fence))
        .thenAnswer((_) async => session);
    when(
      () => service.logout(
        expectedIdentity: session.identity,
        explicitLogoutSession: session,
      ),
    ).thenThrow(
      const NetworkException(
        message: 'offline',
        kind: NetworkFailureKind.offline,
      ),
    );
    when(() => storage.finishExplicitLogout(fence))
        .thenAnswer((_) async => true);

    expect(await repository.logout(), isTrue);

    expect(repairs, 0);
    verify(() => storage.finishExplicitLogout(fence)).called(1);
  });

  for (final fixture in [
    (name: 'missing-expiry', accessExp: null),
    (
      name: 'near-expiry',
      accessExp: DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
    ),
  ]) {
    test(
        '${fixture.name} logout repairs behind its fence and revokes successor',
        () async {
      final original = _session(
        '1',
        role: 'client',
        sid: 'session-A',
        markerSuffix: '-old',
        accessExp: fixture.accessExp,
      );
      final successor = _session(
        '1',
        role: 'client',
        sid: 'session-A',
        markerSuffix: '-new',
        accessExp: DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 15))
                .millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond,
      );
      final fence = AuthExplicitLogoutFence(
        id: 'logout-${fixture.name}-A',
        owner: original,
      );
      AuthExplicitLogoutFence? repairedFence;
      repository = ClientAuthRepository(
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

final Map<String, dynamic> _profileJson = {
  'id': 'auth-root-1',
  'phone': '+233241234567',
  'fullName': 'Client User',
  'languagePref': 'en',
  'status': 'active',
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-07-24T00:00:00.000Z',
  'client': {
    'id': 'client-1',
    'ghanaCardVerified': false,
    'kycStatus': 'not_started',
    'languagePref': 'en',
  },
};
