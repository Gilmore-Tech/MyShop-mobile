import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  test('REFRESH_IN_FLIGHT retries without clearing or logging out', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final storage = _MockTokenStorage();
    var requests = 0;
    var forcedLogouts = 0;

    when(() => storage.readRefreshToken())
        .thenAnswer((_) async => 'refresh-old');
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

    when(() => storage.readRefreshToken())
        .thenAnswer((_) async => 'refresh-old');
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
}
