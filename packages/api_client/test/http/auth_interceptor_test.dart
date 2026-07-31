import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockTokenRefresher extends Mock implements TokenRefresher {}

class _RecordingAdapter implements HttpClientAdapter {
  final List<String> paths = [];
  final List<String?> authorizationHeaders = [];
  Future<ResponseBody> Function(RequestOptions options, int requestNumber)?
      responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    authorizationHeaders.add(
      options.headers['Authorization']?.toString(),
    );
    final custom = responder;
    if (custom != null) return custom(options, paths.length);
    return _jsonResponse(200, '{"success":true,"data":{}}');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _MockTokenStorage tokenStorage;
  late _MockTokenRefresher tokenRefresher;
  late _RecordingAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    tokenStorage = _MockTokenStorage();
    tokenRefresher = _MockTokenRefresher();
    adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(
        tokenStorage: tokenStorage,
        dio: dio,
        tokenRefresher: tokenRefresher,
      ),
    );
  });

  tearDown(() => dio.close());

  test('allows OTP channel discovery and resend without an access token',
      () async {
    await dio.get('/auth/otp/channels');
    await dio.post(
      '/auth/otp/resend',
      data: {'phone': '+233241234567', 'channel': 'whatsapp'},
    );

    expect(adapter.paths, ['/auth/otp/channels', '/auth/otp/resend']);
    verifyNever(() => tokenStorage.readTokenSnapshot());
  });

  test('allows registration legal documents without an access token', () async {
    await dio.get(
      '/legal/required',
      queryParameters: {'role': 'client'},
    );
    await dio.get(
      '/legal/terms',
      queryParameters: {'audience': 'client'},
    );

    expect(adapter.paths, ['/legal/required', '/legal/terms']);
    verifyNever(() => tokenStorage.readTokenSnapshot());
  });

  test('keeps legal consent endpoints authenticated', () async {
    when(() => tokenStorage.readTokenSnapshot()).thenAnswer(
      (_) async => const AuthTokenSnapshot.empty(),
    );

    await expectLater(
      dio.get('/legal/consent/status'),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having((error) => error.error, 'error', 'NOT_AUTHENTICATED'),
      ),
    );

    expect(adapter.paths, isEmpty);
    verify(() => tokenStorage.readTokenSnapshot()).called(1);
  });

  test('does not treat the deleted-role recovery path as public', () async {
    when(() => tokenStorage.readTokenSnapshot()).thenAnswer(
      (_) async => const AuthTokenSnapshot.empty(),
    );

    await expectLater(
      dio.post(
        '/auth/recover',
        data: {'phone': '+233241234567', 'role': 'client'},
      ),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having((error) => error.error, 'error', 'NOT_AUTHENTICATED'),
      ),
    );

    expect(adapter.paths, isEmpty);
    verify(() => tokenStorage.readTokenSnapshot()).called(1);
  });

  test('recovers an identifiable refresh-only session before a request',
      () async {
    final refreshOnly = _session(
      'A',
      accessVersion: null,
      refreshVersion: 1,
    );
    final repaired = _session(
      'A',
      accessVersion: 2,
      refreshVersion: 2,
    );
    var current = refreshOnly;
    when(() => tokenStorage.readTokenSnapshot())
        .thenAnswer((_) async => current);
    when(
      () => tokenRefresher.refresh(expectedSession: refreshOnly),
    ).thenAnswer((_) async {
      current = repaired;
      return repaired.accessToken;
    });

    await dio.get('/users/me');

    expect(adapter.paths, ['/users/me']);
    expect(
      adapter.authorizationHeaders,
      ['Bearer ${repaired.accessToken}'],
    );
    verify(
      () => tokenRefresher.refresh(expectedSession: refreshOnly),
    ).called(1);
  });

  test('logout binding follows same-SID rotation but never account B',
      () async {
    final originalA = _session(
      'A',
      accessVersion: 1,
      refreshVersion: 1,
    );
    final rotatedA = _session(
      'A',
      accessVersion: 2,
      refreshVersion: 2,
    );
    final sessionB = _session(
      'B',
      accessVersion: 1,
      refreshVersion: 1,
    );
    var current = rotatedA;
    when(() => tokenStorage.readTokenSnapshot())
        .thenAnswer((_) async => current);
    final options = Options(
      extra: {
        AuthInterceptor.expectedSessionIdentityExtra: originalA.identity,
      },
    );

    await dio.post('/auth/logout', options: options);

    expect(adapter.paths, ['/auth/logout']);
    expect(adapter.authorizationHeaders, ['Bearer ${rotatedA.accessToken}']);

    current = sessionB;
    await expectLater(
      dio.post('/auth/logout', options: options),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having((error) => error.error, 'error', 'STALE_AUTH_SESSION'),
      ),
    );
    expect(adapter.paths, ['/auth/logout']);
    expect(
      adapter.authorizationHeaders,
      isNot(contains('Bearer ${sessionB.accessToken}')),
    );
  });

  test('a stale A takeover 401 cannot clear or retry with account B', () async {
    final sessionA = _session(
      'A',
      accessVersion: 1,
      refreshVersion: 1,
    );
    final sessionB = _session(
      'B',
      accessVersion: 1,
      refreshVersion: 1,
    );
    var current = sessionA;
    when(() => tokenStorage.readTokenSnapshot())
        .thenAnswer((_) async => current);
    adapter.responder = (options, requestNumber) async {
      current = sessionB;
      return _jsonResponse(
        401,
        '{"error":{"code":"${AuthErrorCodes.sessionTakenOver}"}}',
      );
    };

    await expectLater(
      dio.get('/users/me'),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having(
              (error) => error.error,
              'error',
              'STALE_AUTH_SESSION',
            ),
      ),
    );

    expect(adapter.paths, ['/users/me']);
    expect(adapter.authorizationHeaders, ['Bearer ${sessionA.accessToken}']);
    expect(current, same(sessionB));
    verifyNever(
      () => tokenStorage.clearAuthTokensOnlyForIdentityIfCurrent(
        sessionA.identity!,
      ),
    );
    verifyNever(
      () => tokenRefresher.refresh(expectedSession: sessionA),
    );
  });

  test('account switch before retry dispatch cancels the A retry', () async {
    final originalA = _session(
      'A',
      accessVersion: 1,
      refreshVersion: 1,
    );
    final rotatedA = _session(
      'A',
      accessVersion: 2,
      refreshVersion: 2,
    );
    final sessionB = _session(
      'B',
      accessVersion: 1,
      refreshVersion: 1,
    );
    var reads = 0;
    when(() => tokenStorage.readTokenSnapshot()).thenAnswer((_) async {
      reads += 1;
      return switch (reads) {
        1 => originalA,
        2 => rotatedA,
        _ => sessionB,
      };
    });
    adapter.responder = (options, requestNumber) async {
      return _jsonResponse(
        401,
        '{"error":{"code":"${AuthErrorCodes.invalidToken}"}}',
      );
    };

    await expectLater(
      dio.get('/users/me'),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having(
              (error) => error.error,
              'error',
              'STALE_AUTH_SESSION',
            ),
      ),
    );

    expect(adapter.paths, ['/users/me']);
    expect(adapter.authorizationHeaders, ['Bearer ${originalA.accessToken}']);
    expect(reads, 3);
    verifyNever(
      () => tokenRefresher.refresh(expectedSession: originalA),
    );
  });

  test('account switch while A retry is in flight suppresses its response',
      () async {
    final originalA = _session(
      'A',
      accessVersion: 1,
      refreshVersion: 1,
    );
    final rotatedA = _session(
      'A',
      accessVersion: 2,
      refreshVersion: 2,
    );
    final sessionB = _session(
      'B',
      accessVersion: 1,
      refreshVersion: 1,
    );
    var current = originalA;
    when(() => tokenStorage.readTokenSnapshot())
        .thenAnswer((_) async => current);
    adapter.responder = (options, requestNumber) async {
      if (requestNumber == 1) {
        current = rotatedA;
        return _jsonResponse(
          401,
          '{"error":{"code":"${AuthErrorCodes.invalidToken}"}}',
        );
      }
      current = sessionB;
      return _jsonResponse(200, '{"success":true,"data":{}}');
    };

    await expectLater(
      dio.get('/users/me'),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having(
              (error) => error.error,
              'error',
              'STALE_AUTH_SESSION',
            ),
      ),
    );

    expect(adapter.paths, ['/users/me', '/users/me']);
    expect(
      adapter.authorizationHeaders,
      [
        'Bearer ${originalA.accessToken}',
        'Bearer ${rotatedA.accessToken}',
      ],
    );
    expect(
      adapter.authorizationHeaders,
      isNot(contains('Bearer ${sessionB.accessToken}')),
    );
    expect(current, same(sessionB));
    verifyNever(
      () => tokenRefresher.refresh(expectedSession: originalA),
    );
  });
}

ResponseBody _jsonResponse(int status, String body) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

AuthTokenSnapshot _session(
  String account, {
  required int? accessVersion,
  required int refreshVersion,
}) {
  final subject = 'auth-root-$account';
  final roleAccountId = 'client-account-$account';
  final sid = 'session-$account';
  return AuthTokenSnapshot(
    accessToken: accessVersion == null
        ? null
        : _jwt(
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
