import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  test('REFRESH_IN_FLIGHT 401 retries without clearing or logging out',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    var requests = 0;
    var forcedLogouts = 0;
    final attemptIds = <String>[];
    final original = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotated = _session('A', accessVersion: 2, refreshVersion: 2);
    var current = original;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(
      () => storage.replaceTokensIfCurrent(
        expected: original,
        accessToken: rotated.accessToken!,
        refreshToken: rotated.refreshToken!,
      ),
    ).thenAnswer((_) async {
      if (!current.isExactCredentialState(original)) return false;
      current = rotated;
      return true;
    });

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests += 1;
          attemptIds.add(
            (options.data as Map<String, dynamic>)['refreshAttemptId']
                as String,
          );
          if (requests == 1) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 401,
                  data: {
                    'error': {'code': AuthErrorCodes.refreshInFlight},
                  },
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': rotated.accessToken,
                  'refreshToken': rotated.refreshToken,
                },
              },
            ),
          );
        },
      ),
    );

    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (_) => forcedLogouts += 1,
      delay: (_) async {},
    );

    await expectLater(
      refresher.refresh(expectedSession: original),
      completion(rotated.accessToken),
    );

    expect(requests, 2);
    expect(attemptIds.toSet(), hasLength(1));
    expect(isCanonicalRefreshAttemptId(attemptIds.first), isTrue);
    expect(forcedLogouts, 0);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
    verifyNever(() => storage.clearTokensIfCurrent(original));
    verifyNever(() => storage.clearAuthTokensOnlyIfCurrent(original));
    verify(
      () => storage.replaceTokensIfCurrent(
        expected: original,
        accessToken: rotated.accessToken!,
        refreshToken: rotated.refreshToken!,
      ),
    ).called(1);
  });

  test('exhausted REFRESH_IN_FLIGHT 401 preserves the session', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    var forcedLogouts = 0;
    var requests = 0;
    final original = _session('A', accessVersion: 1, refreshVersion: 1);

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => original);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests += 1;
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'error': {'code': AuthErrorCodes.refreshInFlight},
                },
              ),
            ),
          );
        },
      ),
    );

    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (_) => forcedLogouts += 1,
      delay: (_) async {},
    );

    await expectLater(
      refresher.refresh(expectedSession: original),
      completion(isNull),
    );

    expect(requests, 3);
    expect(forcedLogouts, 0);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
    verifyNever(() => storage.clearTokensIfCurrent(original));
    verifyNever(() => storage.clearAuthTokensOnlyIfCurrent(original));
  });

  test('bootstrap upgrades a pre-SID refresh token to one full identity',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final legacyA = _legacyPair('A', role: 'client');
    final upgradedA = _session('A', accessVersion: 1, refreshVersion: 1);
    var current = legacyA;
    Object? requestBody;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(
      () => storage.replaceLegacyTokensIfCurrent(
        expected: legacyA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).thenAnswer((_) async {
      if (!current.hasExactRawCredentials(legacyA)) return false;
      current = upgradedA;
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestBody = options.data;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': upgradedA.accessToken,
                  'refreshToken': upgradedA.refreshToken,
                },
              },
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    await expectLater(
      refresher.refreshForBootstrap(expectedSession: legacyA),
      completion(upgradedA.accessToken),
    );

    expect(current.identity, upgradedA.identity);
    final body = requestBody as Map<String, dynamic>;
    expect(body['refreshToken'], legacyA.refreshToken);
    expect(body, isNot(contains('accessToken')));
    expect(
      isCanonicalRefreshAttemptId(body['refreshAttemptId'] as String),
      isTrue,
    );
    verify(
      () => storage.replaceLegacyTokensIfCurrent(
        expected: legacyA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).called(1);
    verifyNever(
      () => storage.replaceTokensIfCurrent(
        expected: legacyA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    );
  });

  test('bootstrap split upgrade sends exact access proof and persists same SID',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final interruptedA = _interruptedUpgrade(
      'A',
      role: 'client',
      sid: 'session-A',
    );
    final upgradedA = _session('A', accessVersion: 2, refreshVersion: 2);
    var current = interruptedA;
    Object? requestBody;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(
      () => storage.replaceInterruptedLegacyTokensIfCurrent(
        expected: interruptedA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).thenAnswer((_) async {
      if (!current.hasExactRawCredentials(interruptedA)) return false;
      current = upgradedA;
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestBody = options.data;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': upgradedA.accessToken,
                  'refreshToken': upgradedA.refreshToken,
                },
              },
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    await expectLater(
      refresher.refreshForBootstrap(expectedSession: interruptedA),
      completion(upgradedA.accessToken),
    );

    expect(
      requestBody,
      allOf(
        containsPair('refreshToken', interruptedA.refreshToken),
        containsPair('accessToken', interruptedA.accessToken),
        contains('refreshAttemptId'),
      ),
    );
    expect(
      isCanonicalRefreshAttemptId(
        (requestBody as Map<String, dynamic>)['refreshAttemptId'] as String,
      ),
      isTrue,
    );
    expect(
      current.identity?.generation,
      interruptedA.accessLineage?.generation,
    );
    verify(
      () => storage.replaceInterruptedLegacyTokensIfCurrent(
        expected: interruptedA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).called(1);
  });

  test('ordinary refresh neither sends nor attempts a split legacy upgrade',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final interruptedA = _interruptedUpgrade(
      'A',
      role: 'client',
      sid: 'session-A',
    );
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests += 1;
          handler.resolve(
            Response<dynamic>(requestOptions: options, statusCode: 200),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    await expectLater(
      refresher.refresh(expectedSession: interruptedA),
      completion(isNull),
    );

    expect(requests, 0);
    verifyNever(() => storage.readTokenSnapshot());
    verifyNever(
      () => storage.replaceInterruptedLegacyTokensIfCurrent(
        expected: interruptedA,
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    );
  });

  test('ordinary full-SID refresh sends exact predecessor proof', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final original = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotated = _session('A', accessVersion: 2, refreshVersion: 2);
    var current = original;
    Object? requestBody;
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(
      () => storage.replaceTokensIfCurrent(
        expected: original,
        accessToken: rotated.accessToken!,
        refreshToken: rotated.refreshToken!,
      ),
    ).thenAnswer((_) async {
      current = rotated;
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestBody = options.data;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': rotated.accessToken,
                  'refreshToken': rotated.refreshToken,
                },
              },
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    await refresher.refresh(expectedSession: original);

    expect(
      (requestBody as Map<String, dynamic>),
      allOf(
        containsPair('refreshToken', original.refreshToken),
        containsPair('accessToken', original.accessToken),
        contains('refreshAttemptId'),
      ),
    );
    expect(
      isCanonicalRefreshAttemptId(
        (requestBody as Map<String, dynamic>)['refreshAttemptId'] as String,
      ),
      isTrue,
    );
  });

  for (final fixture in [
    (
      name: 'both missing',
      accessHasRoleAccount: false,
      refreshHasRoleAccount: false,
    ),
    (
      name: 'access-only',
      accessHasRoleAccount: true,
      refreshHasRoleAccount: false,
    ),
    (
      name: 'refresh-only',
      accessHasRoleAccount: false,
      refreshHasRoleAccount: true,
    ),
  ]) {
    test('bootstrap role-account upgrade ${fixture.name} sends SID proof',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      final storage = _MockTokenStorage();
      final legacy = _roleAccountUpgrade(
        'A',
        accessHasRoleAccount: fixture.accessHasRoleAccount,
        refreshHasRoleAccount: fixture.refreshHasRoleAccount,
      );
      final upgraded = _session('A', accessVersion: 2, refreshVersion: 2);
      var current = legacy;
      Object? requestBody;
      when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
      when(
        () => storage.replaceSessionLineageTokensIfCurrent(
          expected: legacy,
          accessToken: upgraded.accessToken!,
          refreshToken: upgraded.refreshToken!,
        ),
      ).thenAnswer((_) async {
        if (!current.hasExactRawCredentials(legacy)) return false;
        current = upgraded;
        return true;
      });
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestBody = options.data;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {
                    'accessToken': upgraded.accessToken,
                    'refreshToken': upgraded.refreshToken,
                  },
                },
              ),
            );
          },
        ),
      );
      final refresher = TokenRefresher(
        dio: dio,
        tokenStorage: storage,
      );

      await expectLater(
        refresher.refreshForBootstrap(expectedSession: legacy),
        completion(upgraded.accessToken),
      );

      expect(
        requestBody as Map<String, dynamic>,
        allOf(
          containsPair('refreshToken', legacy.refreshToken),
          containsPair('accessToken', legacy.accessToken),
          contains('refreshAttemptId'),
        ),
      );
      expect(
        isCanonicalRefreshAttemptId(
          (requestBody as Map<String, dynamic>)['refreshAttemptId'] as String,
        ),
        isTrue,
      );
      expect(current.identity, upgraded.identity);
    });
  }

  test('ordinary refresh refuses a pre-SID token without a network call',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final legacyA = _legacyRefreshOnly('A', role: 'client');
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests += 1;
          handler.resolve(
            Response<dynamic>(requestOptions: options, statusCode: 200),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    await expectLater(
      refresher.refresh(expectedSession: legacyA),
      completion(isNull),
    );

    expect(requests, 0);
    verifyNever(() => storage.readTokenSnapshot());
  });

  test('terminal bootstrap response clears the exact legacy owner', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final legacyA = _legacyRefreshOnly('A', role: 'client');
    var current = legacyA;
    var forcedLogouts = 0;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(() => storage.clearTokensIfCurrent(legacyA)).thenAnswer((_) async {
      if (!current.hasExactRawCredentials(legacyA)) return false;
      current = const AuthTokenSnapshot.empty();
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 401,
              data: {
                'error': {'code': AuthErrorCodes.tokenExpired},
              },
            ),
          ),
        ),
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (_) => forcedLogouts += 1,
    );

    await expectLater(
      refresher.refreshForBootstrap(expectedSession: legacyA),
      completion(isNull),
    );

    expect(current.hasCredentials, isFalse);
    expect(forcedLogouts, 1);
    verify(() => storage.clearTokensIfCurrent(legacyA)).called(1);
    verifyNever(() => storage.clearAuthTokensOnlyIfCurrent(legacyA));
  });

  test('invalid interrupted bootstrap proof full-clears its exact owner',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final owner = _interruptedUpgrade(
      'A',
      role: 'client',
      sid: 'session-A',
    );
    var forcedLogouts = 0;
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => owner);
    when(() => storage.clearTokensIfCurrent(owner))
        .thenAnswer((_) async => true);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 401,
              data: {
                'error': {
                  'code': AuthErrorCodes.legacyBootstrapProofInvalid,
                },
              },
            ),
          ),
        ),
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (_) => forcedLogouts += 1,
    );

    await expectLater(
      refresher.refreshForBootstrap(expectedSession: owner),
      completion(isNull),
    );

    expect(forcedLogouts, 1);
    verify(() => storage.clearTokensIfCurrent(owner)).called(1);
    verifyNever(() => storage.clearAuthTokensOnlyIfCurrent(owner));
  });

  test('force-logout dispatch survives a post-clear storage read failure',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final owner = _session('A', accessVersion: 1, refreshVersion: 1);
    var cleared = false;
    AuthForceLogoutEvent? event;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async {
      if (cleared) {
        throw StateError('secure storage unavailable after clear');
      }
      return owner;
    });
    when(() => storage.clearTokensIfCurrent(owner)).thenAnswer((_) async {
      cleared = true;
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 401,
              data: {
                'error': {'code': AuthErrorCodes.invalidToken},
              },
            ),
          ),
        ),
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (value) => event = value,
    );

    await expectLater(
      refresher.refresh(expectedSession: owner),
      completion(isNull),
    );

    expect(cleared, isTrue);
    expect(event?.generation, owner.identity?.generation);
    verify(() => storage.readTokenSnapshot()).called(3);
  });

  test('code-less 401 preserves credentials and does not force logout',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final owner = _session('A', accessVersion: 1, refreshVersion: 1);
    var forcedLogouts = 0;
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => owner);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 401,
              data: const {'message': 'edge response was truncated'},
            ),
          ),
        ),
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (_) => forcedLogouts += 1,
    );

    await expectLater(
      refresher.refresh(expectedSession: owner),
      completion(isNull),
    );

    expect(forcedLogouts, 0);
    verifyNever(() => storage.clearTokensIfCurrent(owner));
    verifyNever(() => storage.clearAuthTokensOnlyIfCurrent(owner));
  });

  test('explicit SESSION_TAKEN_OVER soft-clears only the exact JWT owner',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final owner = _session('A', accessVersion: 1, refreshVersion: 1);
    AuthForceLogoutEvent? event;
    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => owner);
    when(
      () => storage.clearAuthTokensOnlyForIdentityIfCurrent(owner.identity!),
    ).thenAnswer((_) async => true);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 401,
              data: {
                'error': {'code': AuthErrorCodes.sessionTakenOver},
              },
            ),
          ),
        ),
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (value) => event = value,
    );

    await expectLater(
      refresher.refresh(expectedSession: owner),
      completion(isNull),
    );

    expect(event?.generation, owner.identity?.generation);
    verify(
      () => storage.clearAuthTokensOnlyForIdentityIfCurrent(owner.identity!),
    ).called(1);
    verifyNever(() => storage.clearTokensIfCurrent(owner));
  });

  for (final terminalCode in const [
    AuthErrorCodes.userNotFound,
    AuthErrorCodes.roleAccountUnavailable,
    AuthErrorCodes.roleAccountMismatch,
  ]) {
    test('$terminalCode full-clears only its exact credential owner', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      final storage = _MockTokenStorage();
      final owner = _session('A', accessVersion: 1, refreshVersion: 1);
      var forcedLogouts = 0;
      when(() => storage.readTokenSnapshot()).thenAnswer((_) async => owner);
      when(() => storage.clearTokensIfCurrent(owner))
          .thenAnswer((_) async => true);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'error': {'code': terminalCode},
                },
              ),
            ),
          ),
        ),
      );
      final refresher = TokenRefresher(
        dio: dio,
        tokenStorage: storage,
        onForceLogout: (_) => forcedLogouts += 1,
      );

      await expectLater(
        refresher.refresh(expectedSession: owner),
        completion(isNull),
      );

      expect(forcedLogouts, 1);
      verify(() => storage.clearTokensIfCurrent(owner)).called(1);
      verifyNever(
        () => storage.clearAuthTokensOnlyForIdentityIfCurrent(owner.identity!),
      );
    });
  }

  test('late account A refresh cannot overwrite account B', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final originalA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    var current = originalA;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(
      () => storage.replaceTokensIfCurrent(
        expected: originalA,
        accessToken: rotatedA.accessToken!,
        refreshToken: rotatedA.refreshToken!,
      ),
    ).thenAnswer((_) async {
      if (!current.isExactCredentialState(originalA)) return false;
      current = rotatedA;
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await releaseResponse.future;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': rotatedA.accessToken,
                  'refreshToken': rotatedA.refreshToken,
                },
              },
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    final refresh = refresher.refresh(expectedSession: originalA);
    await requestStarted.future;
    current = sessionB;
    releaseResponse.complete();

    await expectLater(refresh, completion(isNull));
    expect(current.isExactCredentialState(sessionB), isTrue);
    verify(
      () => storage.replaceTokensIfCurrent(
        expected: originalA,
        accessToken: rotatedA.accessToken!,
        refreshToken: rotatedA.refreshToken!,
      ),
    ).called(1);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('late terminal response for A neither clears nor logs out B', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final originalA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    var current = originalA;
    var forcedLogouts = 0;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(() => storage.clearTokensIfCurrent(originalA)).thenAnswer((_) async {
      if (!current.isExactCredentialState(originalA)) return false;
      current = const AuthTokenSnapshot.empty();
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await releaseResponse.future;
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'error': {'code': AuthErrorCodes.invalidToken},
                },
              ),
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (_) => forcedLogouts += 1,
    );

    final refresh = refresher.refresh(expectedSession: originalA);
    await requestStarted.future;
    current = sessionB;
    releaseResponse.complete();

    await expectLater(refresh, completion(isNull));
    expect(current.isExactCredentialState(sessionB), isTrue);
    expect(forcedLogouts, 0);
    verify(() => storage.clearTokensIfCurrent(originalA)).called(1);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('late legacy A migration cannot overwrite a new account B', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final legacyA = _legacyRefreshOnly('A', role: 'client');
    final upgradedA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    var current = legacyA;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(
      () => storage.replaceLegacyTokensIfCurrent(
        expected: legacyA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).thenAnswer((_) async {
      if (!current.hasExactRawCredentials(legacyA)) return false;
      current = upgradedA;
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await releaseResponse.future;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': upgradedA.accessToken,
                  'refreshToken': upgradedA.refreshToken,
                },
              },
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    final migration = refresher.refreshForBootstrap(expectedSession: legacyA);
    await requestStarted.future;
    current = sessionB;
    releaseResponse.complete();

    await expectLater(migration, completion(isNull));
    expect(current.isExactCredentialState(sessionB), isTrue);
    verify(
      () => storage.replaceLegacyTokensIfCurrent(
        expected: legacyA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).called(1);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('late interrupted A upgrade cannot overwrite a new account B', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final interruptedA = _interruptedUpgrade(
      'A',
      role: 'client',
      sid: 'session-A',
    );
    final upgradedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    var current = interruptedA;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(
      () => storage.replaceInterruptedLegacyTokensIfCurrent(
        expected: interruptedA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).thenAnswer((_) async {
      if (!current.hasExactRawCredentials(interruptedA)) return false;
      current = upgradedA;
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await releaseResponse.future;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': upgradedA.accessToken,
                  'refreshToken': upgradedA.refreshToken,
                },
              },
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
    );

    final migration =
        refresher.refreshForBootstrap(expectedSession: interruptedA);
    await requestStarted.future;
    current = sessionB;
    releaseResponse.complete();

    await expectLater(migration, completion(isNull));
    expect(current.isExactCredentialState(sessionB), isTrue);
    verify(
      () => storage.replaceInterruptedLegacyTokensIfCurrent(
        expected: interruptedA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
    ).called(1);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('late terminal legacy A response cannot clear account B', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final legacyA = _legacyRefreshOnly('A', role: 'client');
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    var current = legacyA;
    var forcedLogouts = 0;

    when(() => storage.readTokenSnapshot()).thenAnswer((_) async => current);
    when(() => storage.clearTokensIfCurrent(legacyA)).thenAnswer((_) async {
      if (!current.hasExactRawCredentials(legacyA)) return false;
      current = const AuthTokenSnapshot.empty();
      return true;
    });
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!requestStarted.isCompleted) requestStarted.complete();
          await releaseResponse.future;
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'error': {'code': AuthErrorCodes.invalidToken},
                },
              ),
            ),
          );
        },
      ),
    );
    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: (_) => forcedLogouts += 1,
    );

    final migration = refresher.refreshForBootstrap(expectedSession: legacyA);
    await requestStarted.future;
    current = sessionB;
    releaseResponse.complete();

    await expectLater(migration, completion(isNull));
    expect(current.isExactCredentialState(sessionB), isTrue);
    expect(forcedLogouts, 0);
    verify(() => storage.clearTokensIfCurrent(legacyA)).called(1);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });
}

AuthTokenSnapshot _session(
  String account, {
  required int accessVersion,
  required int refreshVersion,
}) {
  final subject = 'auth-root-$account';
  final roleAccountId = 'client-account-$account';
  final sid = 'session-$account';
  return AuthTokenSnapshot(
    accessToken: _jwt(
      subject: subject,
      role: 'client',
      roleAccountId: roleAccountId,
      sid: sid,
      marker: 'access-$accessVersion',
    ),
    refreshToken: _jwt(
      subject: subject,
      role: 'client',
      roleAccountId: roleAccountId,
      sid: sid,
      marker: 'refresh-$refreshVersion',
    ),
    storageFormat: AuthTokenStorageFormat.versioned,
  );
}

AuthTokenSnapshot _legacyRefreshOnly(
  String account, {
  required String role,
}) =>
    AuthTokenSnapshot(
      accessToken: null,
      refreshToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        marker: 'legacy-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.legacy,
    );

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

AuthTokenSnapshot _roleAccountUpgrade(
  String account, {
  required bool accessHasRoleAccount,
  required bool refreshHasRoleAccount,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: 'auth-root-$account',
        role: 'client',
        roleAccountId: 'client-account-$account',
        sid: 'session-$account',
        includeRoleAccountId: accessHasRoleAccount,
        marker: 'legacy-access',
      ),
      refreshToken: _jwt(
        subject: 'auth-root-$account',
        role: 'client',
        roleAccountId: 'client-account-$account',
        sid: 'session-$account',
        includeRoleAccountId: refreshHasRoleAccount,
        marker: 'legacy-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.legacy,
    );

String _jwt({
  required String subject,
  required String role,
  String? roleAccountId,
  String? sid,
  bool includeRoleAccountId = true,
  required String marker,
}) {
  final claims = <String, dynamic>{'sub': subject, 'role': role};
  if (sid != null) claims['sid'] = sid;
  if (sid != null && includeRoleAccountId) {
    claims['roleAccountId'] = roleAccountId ?? '$role-account-for-$subject';
  }
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode(claims),
        ),
      )
      .replaceAll('=', '');
  return 'e30.$payload.$marker';
}
