import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _RecordingAttemptStore implements RefreshAttemptStore {
  _RecordingAttemptStore(this.attemptId);

  final String attemptId;
  String? boundRefreshToken;
  var reads = 0;
  var clears = 0;

  @override
  Future<String> readOrCreate(String refreshToken) async {
    reads += 1;
    boundRefreshToken ??= refreshToken;
    expect(boundRefreshToken, refreshToken);
    return attemptId;
  }

  @override
  Future<void> clearIfMatches({
    required String refreshToken,
    required String attemptId,
  }) async {
    expect(refreshToken, boundRefreshToken);
    expect(attemptId, this.attemptId);
    clears += 1;
    boundRefreshToken = null;
  }
}

void main() {
  test('REFRESH_IN_FLIGHT retries without clearing or logging out', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    var requests = 0;
    var forcedLogouts = 0;
    final attemptIds = <String>[];

    when(
      () => storage.readRefreshToken(),
    ).thenAnswer((_) async => 'refresh-old');
    when(
      () => storage.writeTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});

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
                  'accessToken': 'access-new',
                  'refreshToken': 'refresh-new',
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
      onForceLogout: () => forcedLogouts += 1,
      delay: (_) async {},
    );

    await expectLater(refresher.refresh(), completion('access-new'));

    expect(requests, 2);
    expect(attemptIds, hasLength(2));
    expect(attemptIds.toSet(), hasLength(1));
    expect(isCanonicalRefreshAttemptId(attemptIds.first), isTrue);
    expect(forcedLogouts, 0);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
    verify(
      () => storage.writeTokens(
        accessToken: 'access-new',
        refreshToken: 'refresh-new',
      ),
    ).called(1);
  });

  test('exhausted REFRESH_IN_FLIGHT remains authenticated', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    var forcedLogouts = 0;

    when(
      () => storage.readRefreshToken(),
    ).thenAnswer((_) async => 'refresh-old');
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
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
        ),
      ),
    );

    final refresher = TokenRefresher(
      dio: dio,
      tokenStorage: storage,
      onForceLogout: () => forcedLogouts += 1,
      delay: (_) async {},
    );

    await expectLater(refresher.refresh(), completion(isNull));

    expect(forcedLogouts, 0);
    verifyNever(() => storage.clearTokens());
    verifyNever(() => storage.clearAuthTokensOnly());
  });

  test('ambiguous response loss reuses the durable attempt ID', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final attemptStore = _RecordingAttemptStore(generateRefreshAttemptId());
    final sentAttemptIds = <String>[];
    var requests = 0;

    when(
      () => storage.readRefreshToken(),
    ).thenAnswer((_) async => 'refresh-old');
    when(
      () => storage.writeTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests += 1;
          sentAttemptIds.add(
            (options.data as Map<String, dynamic>)['refreshAttemptId']
                as String,
          );
          if (requests == 1) {
            handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: 'response lost after server commit',
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
                  'accessToken': 'access-new',
                  'refreshToken': 'refresh-new',
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
      refreshAttemptStore: attemptStore,
    );

    await expectLater(refresher.refresh(), completion(isNull));
    expect(attemptStore.clears, 0);
    await expectLater(refresher.refresh(), completion('access-new'));

    expect(sentAttemptIds, [attemptStore.attemptId, attemptStore.attemptId]);
    expect(attemptStore.clears, 1);
  });

  test('concurrent callers share one refresh and one attempt', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    final attemptStore = _RecordingAttemptStore(generateRefreshAttemptId());
    final releaseResponse = Completer<void>();
    final requestStarted = Completer<void>();
    var requests = 0;

    when(
      () => storage.readRefreshToken(),
    ).thenAnswer((_) async => 'refresh-old');
    when(
      () => storage.writeTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests += 1;
          if (!requestStarted.isCompleted) requestStarted.complete();
          expect(
            (options.data as Map<String, dynamic>)['refreshAttemptId'],
            attemptStore.attemptId,
          );
          await releaseResponse.future;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': 'access-new',
                  'refreshToken': 'refresh-new',
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
      refreshAttemptStore: attemptStore,
    );
    final first = refresher.refresh();
    final second = refresher.refresh();
    await requestStarted.future;
    expect(requests, 1);
    releaseResponse.complete();

    await expectLater(
      Future.wait([first, second]),
      completion(['access-new', 'access-new']),
    );
    expect(attemptStore.reads, 1);
    expect(attemptStore.clears, 1);
  });

  test(
    'does not clear the attempt before token-pair persistence succeeds',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      final storage = _MockTokenStorage();
      final attemptStore = _RecordingAttemptStore(generateRefreshAttemptId());

      when(
        () => storage.readRefreshToken(),
      ).thenAnswer((_) async => 'refresh-old');
      when(
        () => storage.writeTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenThrow(StateError('secure storage unavailable'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'accessToken': 'access-new',
                  'refreshToken': 'refresh-new',
                },
              },
            ),
          ),
        ),
      );

      final refresher = TokenRefresher(
        dio: dio,
        tokenStorage: storage,
        refreshAttemptStore: attemptStore,
      );

      await expectLater(refresher.refresh(), completion(isNull));
      expect(attemptStore.clears, 0);
      expect(attemptStore.boundRefreshToken, 'refresh-old');
    },
  );
}
