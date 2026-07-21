import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockTokenRefresher extends Mock implements TokenRefresher {}

class _RecordingAdapter implements HttpClientAdapter {
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      '{"success":true,"data":{}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _MockTokenStorage tokenStorage;
  late _RecordingAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    tokenStorage = _MockTokenStorage();
    adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      AuthInterceptor(
        tokenStorage: tokenStorage,
        dio: dio,
        tokenRefresher: _MockTokenRefresher(),
      ),
    );
  });

  tearDown(() => dio.close());

  test('allows OTP channel discovery and resend without an access token',
      () async {
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => null);

    await dio.get('/auth/otp/channels');
    await dio.post(
      '/auth/otp/resend',
      data: {'phone': '+233241234567', 'channel': 'whatsapp'},
    );

    expect(adapter.paths, ['/auth/otp/channels', '/auth/otp/resend']);
    verifyNever(() => tokenStorage.readAccessToken());
  });

  test('allows registration legal documents without an access token', () async {
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => null);

    await dio.get(
      '/legal/required',
      queryParameters: {'role': 'client'},
    );
    await dio.get(
      '/legal/terms',
      queryParameters: {'audience': 'client'},
    );

    expect(adapter.paths, ['/legal/required', '/legal/terms']);
    verifyNever(() => tokenStorage.readAccessToken());
  });

  test('keeps legal consent endpoints authenticated', () async {
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => null);

    await expectLater(
      dio.get('/legal/consent/status'),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having((error) => error.error, 'error', 'NOT_AUTHENTICATED'),
      ),
    );

    expect(adapter.paths, isEmpty);
    verify(() => tokenStorage.readAccessToken()).called(1);
  });

  test('does not treat the unregistered deleted-role recovery path as public',
      () async {
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => null);

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
    verify(() => tokenStorage.readAccessToken()).called(1);
  });
}
