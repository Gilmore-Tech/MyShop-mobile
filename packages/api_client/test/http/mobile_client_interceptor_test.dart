import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter({this.statusCode = 200, this.body = '{"success":true}'});

  final int statusCode;
  final String body;
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [
          body.trimLeft().startsWith('<')
              ? 'text/html; charset=utf-8'
              : Headers.jsonContentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ErrorAdapter implements HttpClientAdapter {
  _ErrorAdapter(this.type);

  final DioExceptionType type;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(requestOptions: options, type: type);
  }

  @override
  void close({bool force = false}) {}
}

const _healthyReadinessBody = '''
{"success":true,"data":{"status":"healthy","checks":{"database":"ok","redis":"ok"},"timestamp":"2026-07-28T00:00:00.000Z","release":{"version":"1.4.1","commit":"abcdef0"}}}
''';

void main() {
  test(
    'legal-status failures retain distinct offline, timeout and 5xx notice',
    () {
      expect(
        mobileServiceIssueForLegalStatusError(
          const NetworkException(
            message: 'private DNS detail',
            kind: NetworkFailureKind.offline,
          ),
        ),
        MobileServiceIssue.offline,
      );
      expect(
        mobileServiceIssueForLegalStatusError(
          const NetworkException(
            message: 'private timeout detail',
            kind: NetworkFailureKind.timeout,
          ),
        ),
        MobileServiceIssue.timeout,
      );
      expect(
        mobileServiceIssueForLegalStatusError(
          const ServerException(
            message: 'private upstream detail',
            statusCode: 503,
          ),
        ),
        MobileServiceIssue.unavailable,
      );
    },
  );

  test('readiness retry invokes revalidation only after success', () async {
    var revalidations = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);

    dio.httpClientAdapter = _ErrorAdapter(DioExceptionType.connectionError);
    await expectLater(
      probeMobileServiceReadiness(dio, onReady: () => revalidations++),
      throwsA(isA<DioException>()),
    );
    expect(revalidations, 0);

    final ready = _ResponseAdapter(body: _healthyReadinessBody);
    dio.httpClientAdapter = ready;
    await probeMobileServiceReadiness(dio, onReady: () => revalidations++);
    expect(revalidations, 1);
    expect(ready.captured?.path, MobileClientInterceptor.readinessPath);
  });

  test(
    'readiness retry rejects captive, malformed and unhealthy 200 responses',
    () async {
      for (final body in const [
        '<html><body>Sign in to Wi-Fi</body></html>',
        '{"success":true}',
        '{"success":true,"data":null}',
        '{"success":true,"data":{"status":"healthy"}}',
        '{"success":true,"data":{"status":"degraded","checks":{"database":"ok","redis":"ok"}}}',
        '{"success":true,"data":{"status":"healthy","checks":{"database":"error","redis":"ok"}}}',
        '{"success":true,"data":{"status":"healthy","checks":{"database":"ok","redis":"timeout"}}}',
        '{"success":false,"data":{"status":"healthy","checks":{"database":"ok","redis":"ok"}}}',
      ]) {
        var revalidations = 0;
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
        addTearDown(dio.close);
        dio.httpClientAdapter = _ResponseAdapter(body: body);

        await expectLater(
          probeMobileServiceReadiness(dio, onReady: () => revalidations++),
          throwsA(isA<FormatException>()),
          reason: body,
        );
        expect(revalidations, 0, reason: body);
      }
    },
  );

  test(
    'adds app, platform, marketing version and numeric build metadata to API requests',
    () async {
      final adapter = _ResponseAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(
        MobileClientInterceptor(
          app: MobileAppKind.provider,
          onUpdateRequired: (_) {},
          metadataLoader: () async => const MobileClientMetadata(
            app: MobileAppKind.provider,
            platform: MobilePlatform.android,
            version: '1.4.5',
            buildNumber: 21,
          ),
        ),
      );

      await dio.get('/providers/me/availability');

      expect(
        adapter.captured?.headers,
        containsPair('X-MyShop-App', 'provider'),
      );
      expect(
        adapter.captured?.headers,
        containsPair('X-MyShop-Platform', 'android'),
      );
      expect(
        adapter.captured?.headers,
        containsPair('X-MyShop-Version', '1.4.5'),
      );
      expect(adapter.captured?.headers, containsPair('X-MyShop-Build', '21'));
    },
  );

  test('does not send a free-form custom marketing version', () async {
    final adapter = _ResponseAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      MobileClientInterceptor(
        app: MobileAppKind.provider,
        onUpdateRequired: (_) {},
        metadataLoader: () async => const MobileClientMetadata(
          app: MobileAppKind.provider,
          platform: MobilePlatform.android,
          version: 'private typed content',
          buildNumber: 21,
        ),
      ),
    );

    await dio.get('/providers/me/availability');

    expect(adapter.captured?.headers, isNot(contains('X-MyShop-Version')));
    expect(adapter.captured?.headers, containsPair('X-MyShop-Build', '21'));
  });

  test('loads immutable package metadata once across requests', () async {
    var loads = 0;
    final adapter = _ResponseAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      MobileClientInterceptor(
        app: MobileAppKind.client,
        onUpdateRequired: (_) {},
        metadataLoader: () async {
          loads++;
          return const MobileClientMetadata(
            app: MobileAppKind.client,
            platform: MobilePlatform.ios,
            buildNumber: 20,
          );
        },
      ),
    );

    await Future.wait([dio.get('/one'), dio.get('/two')]);

    expect(loads, 1);
  });

  test(
    'surfaces only the stable 426 update contract with a safe store URL',
    () async {
      final updates = <AppUpdateRequirement>[];
      final adapter = _ResponseAdapter(
        statusCode: 426,
        body: '''
        {"success":false,"error":{"code":"APP_UPDATE_REQUIRED","message":"Update now.","details":{"app":"client","platform":"ios","minimumBuild":22,"currentBuild":20,"storeUrl":"https://apps.example.test/client"}}}
      ''',
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(
        MobileClientInterceptor(
          app: MobileAppKind.client,
          onUpdateRequired: updates.add,
          metadataLoader: () async => const MobileClientMetadata(
            app: MobileAppKind.client,
            platform: MobilePlatform.ios,
            buildNumber: 20,
          ),
        ),
      );

      await expectLater(dio.get('/rides'), throwsA(isA<DioException>()));

      expect(updates, hasLength(1));
      expect(updates.single.message, MobileClientInterceptor.safeUpdateMessage);
      expect(updates.single.message, isNot(contains('Update now.')));
      expect(updates.single.app, MobileAppKind.client);
      expect(updates.single.platform, MobilePlatform.ios);
      expect(updates.single.minimumBuild, 22);
      expect(updates.single.currentBuild, 20);
      expect(
        updates.single.storeUrl,
        Uri.parse('https://apps.example.test/client'),
      );
    },
  );

  test('does not surface spoofed codes or non-HTTPS store links', () async {
    final updates = <AppUpdateRequirement>[];
    final adapter = _ResponseAdapter(
      statusCode: 426,
      body:
          '{"error":{"code":"OTHER_ERROR","details":{"storeUrl":"javascript:alert(1)"}}}',
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      MobileClientInterceptor(
        app: MobileAppKind.client,
        onUpdateRequired: updates.add,
        metadataLoader: () async => const MobileClientMetadata(
          app: MobileAppKind.client,
          platform: MobilePlatform.android,
          buildNumber: 20,
        ),
      ),
    );

    await expectLater(dio.get('/rides'), throwsA(isA<DioException>()));

    expect(updates, isEmpty);
  });

  test('metadata plugin failure leaves enforcement to the server', () async {
    final adapter = _ResponseAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(
      MobileClientInterceptor(
        app: MobileAppKind.client,
        onUpdateRequired: (_) {},
        metadataLoader: () async => throw StateError('plugin unavailable'),
      ),
    );

    await dio.get('/config/public');

    expect(adapter.captured?.headers, isNot(contains('X-MyShop-App')));
    expect(adapter.captured?.headers, isNot(contains('X-MyShop-Platform')));
    expect(adapter.captured?.headers, isNot(contains('X-MyShop-Build')));
  });

  test(
    'reports any intercepted network failure without backend prose',
    () async {
      final issues = <MobileServiceIssue>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      dio.httpClientAdapter = _ErrorAdapter(DioExceptionType.connectionError);
      dio.interceptors.add(
        MobileClientInterceptor(
          app: MobileAppKind.client,
          onUpdateRequired: (_) {},
          onServiceIssue: issues.add,
          metadataLoader: () async => const MobileClientMetadata(
            app: MobileAppKind.client,
            platform: MobilePlatform.android,
            buildNumber: 25,
          ),
        ),
      );

      await expectLater(dio.get('/any-feature'), throwsA(isA<DioException>()));

      expect(issues, [MobileServiceIssue.offline]);
    },
  );

  test('reports timeouts distinctly from an offline connection', () async {
    final issues = <MobileServiceIssue>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.httpClientAdapter = _ErrorAdapter(DioExceptionType.receiveTimeout);
    dio.interceptors.add(
      MobileClientInterceptor(
        app: MobileAppKind.client,
        onUpdateRequired: (_) {},
        onServiceIssue: issues.add,
        metadataLoader: () async => const MobileClientMetadata(
          app: MobileAppKind.client,
          platform: MobilePlatform.android,
          buildNumber: 25,
        ),
      ),
    );

    await expectLater(dio.get('/slow-feature'), throwsA(isA<DioException>()));

    expect(issues, [MobileServiceIssue.timeout]);
  });

  test('only the exact readiness response clears a transport outage', () async {
    final issues = <MobileServiceIssue>[];
    var recoveries = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      MobileClientInterceptor(
        app: MobileAppKind.provider,
        onUpdateRequired: (_) {},
        onServiceIssue: issues.add,
        onServiceRecovered: () => recoveries++,
        metadataLoader: () async => const MobileClientMetadata(
          app: MobileAppKind.provider,
          platform: MobilePlatform.ios,
          buildNumber: 25,
        ),
      ),
    );

    dio.httpClientAdapter = _ErrorAdapter(DioExceptionType.connectionError);
    await expectLater(dio.get('/feature'), throwsA(isA<DioException>()));
    expect(issues, [MobileServiceIssue.offline]);

    final ready = _ResponseAdapter(body: _healthyReadinessBody);
    dio.httpClientAdapter = ready;
    await dio.get('/unrelated-background-poll');
    expect(recoveries, 0);

    await dio.get(MobileClientInterceptor.readinessPath);
    expect(recoveries, 1);
    expect(ready.captured?.path, MobileClientInterceptor.readinessPath);
  });

  test('malformed readiness 200 never clears a transport outage', () async {
    for (final body in const [
      '<html><body>Captive portal</body></html>',
      '{"success":true}',
      '{"success":true,"data":{"status":"healthy","checks":{"database":"ok"}}}',
      '{"success":true,"data":{"status":"degraded","checks":{"database":"ok","redis":"ok"}}}',
      '{"success":true,"data":{"status":"healthy","checks":{"database":"ok","redis":"error"}}}',
    ]) {
      var recoveries = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      dio.interceptors.add(
        MobileClientInterceptor(
          app: MobileAppKind.client,
          onUpdateRequired: (_) {},
          onServiceRecovered: () => recoveries++,
          metadataLoader: () async => const MobileClientMetadata(
            app: MobileAppKind.client,
            platform: MobilePlatform.ios,
            buildNumber: 25,
          ),
        ),
      );
      dio.httpClientAdapter = _ResponseAdapter(body: body);

      await dio.get(MobileClientInterceptor.readinessPath);

      expect(recoveries, 0, reason: body);
    }
  });

  test(
    'every feature HTTP 503 stays feature-scoped, regardless of its body',
    () async {
      for (final body in const [
        '{"error":{"code":"NO_DRIVERS_AVAILABLE","message":"raw backend copy"}}',
        '{"error":{"code":"FUTURE_SCOPED_FEATURE_DISABLED"}}',
        '{"error":{"code":"UNEXPECTED_DEPENDENCY_FAILURE"}}',
        '{"error":{"code":"NO DRIVERS AVAILABLE"}}',
        '{"message":"malicious free-form response"}',
      ]) {
        final issues = <MobileServiceIssue>[];
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
        dio.httpClientAdapter = _ResponseAdapter(statusCode: 503, body: body);
        dio.interceptors.add(
          MobileClientInterceptor(
            app: MobileAppKind.client,
            onUpdateRequired: (_) {},
            onServiceIssue: issues.add,
            metadataLoader: () async => const MobileClientMetadata(
              app: MobileAppKind.client,
              platform: MobilePlatform.android,
              buildNumber: 25,
            ),
          ),
        );

        await expectLater(dio.get('/feature'), throwsA(isA<DioException>()));
        expect(issues, isEmpty);
        dio.close();
      }
    },
  );

  test('does not report deliberate request cancellation as offline', () async {
    final issues = <MobileServiceIssue>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.httpClientAdapter = _ErrorAdapter(DioExceptionType.cancel);
    dio.interceptors.add(
      MobileClientInterceptor(
        app: MobileAppKind.client,
        onUpdateRequired: (_) {},
        onServiceIssue: issues.add,
        metadataLoader: () async => const MobileClientMetadata(
          app: MobileAppKind.client,
          platform: MobilePlatform.android,
          buildNumber: 25,
        ),
      ),
    );

    await expectLater(dio.get('/cancelled'), throwsA(isA<DioException>()));

    expect(issues, isEmpty);
  });
}
