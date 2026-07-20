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
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('adds app, platform and numeric build metadata to API requests',
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
          buildNumber: 21,
        ),
      ),
    );

    await dio.get('/providers/me/availability');

    expect(adapter.captured?.headers, containsPair('X-MyShop-App', 'provider'));
    expect(
      adapter.captured?.headers,
      containsPair('X-MyShop-Platform', 'android'),
    );
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

  test('surfaces only the stable 426 update contract with a safe store URL',
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
    expect(updates.single.message, 'Update now.');
    expect(updates.single.app, MobileAppKind.client);
    expect(updates.single.platform, MobilePlatform.ios);
    expect(updates.single.minimumBuild, 22);
    expect(updates.single.currentBuild, 20);
    expect(
      updates.single.storeUrl,
      Uri.parse('https://apps.example.test/client'),
    );
  });

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
}
