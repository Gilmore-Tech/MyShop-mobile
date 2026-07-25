import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/src/auth/device_id.dart';
import 'package:api_client/src/services/system_telemetry_service.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

class _MockDeviceIdProvider extends Mock implements DeviceIdProvider {}

class _RecordingAdapter implements HttpClientAdapter {
  int statusCode = 200;
  final List<int> statusCodes = [];
  final List<int> acceptedCounts = [];
  Object? failure;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failure != null) throw failure!;
    final responseStatus =
        statusCodes.isEmpty ? statusCode : statusCodes.removeAt(0);
    final payload = options.data is Map ? options.data as Map : const {};
    final events = payload['events'];
    final defaultAccepted = events is List ? events.length : 0;
    final accepted =
        acceptedCounts.isEmpty ? defaultAccepted : acceptedCounts.removeAt(0);
    return ResponseBody.fromString(
      '{"accepted":$accepted}',
      responseStatus,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('formatSystemTelemetryAppVersion', () {
    test('adds a bounded source marker for a reviewed full commit', () {
      expect(
        formatSystemTelemetryAppVersion(
          '1.4.2',
          '101',
          sourceCommit: 'ABCDEF0123456789ABCDEF0123456789ABCDEF01',
        ),
        '1.4.2+101@abcdef012345',
      );
    });

    test('omits missing or malformed source markers', () {
      expect(formatSystemTelemetryAppVersion('1.4.2', '101'), '1.4.2+101');
      expect(
        formatSystemTelemetryAppVersion(
          '1.4.2',
          '101',
          sourceCommit: 'not-a-reviewed-commit',
        ),
        '1.4.2+101',
      );
    });
  });

  group('normaliseSystemTelemetryScreenRoute', () {
    test('keeps route templates and removes query or fragment data', () {
      expect(
        normaliseSystemTelemetryScreenRoute(
          '/profile/support/tickets/:ticketId?token=secret#message',
        ),
        '/profile/support/tickets/:ticketId',
      );
    });

    test('redacts concrete UUID, long hex and numeric route identifiers', () {
      expect(
        normaliseSystemTelemetryScreenRoute(
          '/calls/60dc0918-6b5a-44ea-ae3a-465cde852400',
        ),
        '/calls/:id',
      );
      expect(
        normaliseSystemTelemetryScreenRoute(
          '/documents/0123456789abcdef01234567',
        ),
        '/documents/:id',
      );
      expect(
        normaliseSystemTelemetryScreenRoute('/tickets/233204962227'),
        '/tickets/:id',
      );
    });
  });

  group('SystemTelemetryService', () {
    late Dio dio;
    late _RecordingAdapter adapter;
    late _MockDeviceIdProvider deviceIdProvider;
    late SystemTelemetryService service;

    setUp(() {
      adapter = _RecordingAdapter();
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      dio.httpClientAdapter = adapter;
      deviceIdProvider = _MockDeviceIdProvider();
      when(
        () => deviceIdProvider.ensureDeviceId(),
      ).thenAnswer((_) async => 'install-id');
      service = SystemTelemetryService(
        dio: dio,
        deviceIdProvider: deviceIdProvider,
        app: 'provider',
        packageInfoLoader: () async => PackageInfo(
          appName: 'MyShop Provider',
          packageName: 'com.gilmoretech.myshopprovider',
          version: '1.4.2',
          buildNumber: '101',
        ),
      );
    });

    tearDown(() {
      service.dispose();
      dio.close();
    });

    test(
      'sends bounded privacy-minimal events with release identity',
      () async {
        service.trackScreen(
          '/calls/60dc0918-6b5a-44ea-ae3a-465cde852400?otp=123456',
        );
        service.trackAction(
          'driver_cancel_ride_requested',
          outcome: 'not-an-outcome',
          correlationId: 'contains typed content',
          metadata: {
            'vehicleSelected': true,
            'durationSeconds': 12,
            'description': 'typed customer content',
            'phoneNumber': '233204962227',
          },
        );

        await service.flush();

        expect(adapter.requests, hasLength(1));
        expect(
          adapter.requests.single.uri,
          Uri.parse(
            'https://api.example.test/v1/system-audit/mobile/events',
          ),
        );
        final payload = Map<String, dynamic>.from(
          adapter.requests.single.data as Map,
        );
        expect(payload['app'], 'provider');
        expect(payload['appVersion'], '1.4.2+101');
        expect(payload['deviceId'], 'install-id');
        final events = (payload['events'] as List).cast<Map<String, Object?>>();
        expect(events, hasLength(2));
        expect(events.first['action'], '/calls/:id');
        expect(events.first.toString(), isNot(contains('123456')));
        expect(events.last['outcome'], 'failure');
        expect(events.last, isNot(contains('correlationId')));
        expect(events.last['metadata'], {
          'vehicleSelected': true,
          'durationSeconds': 12,
        });
        expect(
          events.last.toString(),
          isNot(contains('typed customer content')),
        );
        expect(events.last.toString(), isNot(contains('233204962227')));
      },
    );

    test(
      'drops permanently rejected events instead of poisoning the queue',
      () async {
        adapter.statusCode = 401;
        service.trackAction('client_login_completed');
        await service.flush();
        adapter.statusCode = 200;
        await service.flush();

        expect(adapter.requests, hasLength(1));
      },
    );

    test('retains transiently failed events for a later retry', () async {
      adapter.statusCode = 503;
      service.trackAction('provider_go_online_requested');
      await service.flush();
      adapter.statusCode = 200;
      await service.flush();

      expect(adapter.requests, hasLength(2));
      final retried = Map<String, dynamic>.from(
        adapter.requests.last.data as Map,
      );
      expect((retried['events'] as List), hasLength(1));
    });

    test(
      'retains a batch when storage returns success with zero accepted',
      () async {
        adapter.acceptedCounts.addAll([0, 1]);
        service.trackAction('provider_go_online_requested');

        await service.flush();
        await service.flush();

        expect(adapter.requests, hasLength(2));
        final retried = Map<String, dynamic>.from(
          adapter.requests.last.data as Map,
        );
        expect((retried['events'] as List), hasLength(1));
      },
    );

    test(
      'retains the complete batch unless every event is accepted',
      () async {
        adapter.acceptedCounts.addAll([1, 2]);
        service.trackAction('provider_go_online_requested');
        service.trackAction('provider_go_offline_requested');

        await service.flush();
        await service.flush();

        expect(adapter.requests, hasLength(2));
        final retried = Map<String, dynamic>.from(
          adapter.requests.last.data as Map,
        );
        expect((retried['events'] as List), hasLength(2));
      },
    );

    test(
      'keeps offline delivery non-blocking and retries the same event',
      () async {
        adapter.failure = const SocketException('offline');
        service.trackAction('provider_go_offline_requested');

        await expectLater(service.flush(), completes);
        adapter.failure = null;
        await service.flush();

        expect(adapter.requests, hasLength(2));
        final retried = Map<String, dynamic>.from(
          adapter.requests.last.data as Map,
        );
        expect((retried['events'] as List), hasLength(1));
      },
    );

    test('automatically flushes a low-activity queue', () async {
      service.dispose();
      service = SystemTelemetryService(
        dio: dio,
        deviceIdProvider: deviceIdProvider,
        app: 'provider',
        packageInfoLoader: () async => PackageInfo(
          appName: 'MyShop Provider',
          packageName: 'com.gilmoretech.myshopprovider',
          version: '1.4.2',
          buildNumber: '101',
        ),
        delayResolver: (_) => Duration.zero,
      );

      service.trackAction('provider_go_online_requested');
      await _waitForRequests(adapter, 1);

      expect(adapter.requests, hasLength(1));
    });

    test('automatically retries one transiently rejected batch', () async {
      service.dispose();
      service = SystemTelemetryService(
        dio: dio,
        deviceIdProvider: deviceIdProvider,
        app: 'provider',
        packageInfoLoader: () async => PackageInfo(
          appName: 'MyShop Provider',
          packageName: 'com.gilmoretech.myshopprovider',
          version: '1.4.2',
          buildNumber: '101',
        ),
        delayResolver: (_) => Duration.zero,
      );
      adapter.statusCodes.addAll([503, 200]);

      service.trackAction('provider_go_offline_requested');
      await _waitForRequests(adapter, 2);

      expect(adapter.requests, hasLength(2));
      final retried = Map<String, dynamic>.from(
        adapter.requests.last.data as Map,
      );
      expect((retried['events'] as List), hasLength(1));
    });

    test(
      'queues without a timer request until delivery is authenticated',
      () async {
        service.dispose();
        var authenticated = false;
        service = SystemTelemetryService(
          dio: dio,
          deviceIdProvider: deviceIdProvider,
          app: 'provider',
          packageInfoLoader: () async => PackageInfo(
            appName: 'MyShop Provider',
            packageName: 'com.gilmoretech.myshopprovider',
            version: '1.4.2',
            buildNumber: '101',
          ),
          delayResolver: (_) => Duration.zero,
          deliveryAuthority: () async => authenticated,
        );

        service.trackScreen('/auth/phone');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(adapter.requests, isEmpty);

        authenticated = true;
        service.trackAction('provider_login_completed');
        await _waitForRequests(adapter, 1);

        final payload = Map<String, dynamic>.from(
          adapter.requests.single.data as Map,
        );
        final events = (payload['events'] as List).cast<Map<String, Object?>>();
        expect(
          events.map((event) => event['action']),
          ['/auth/phone', 'provider_login_completed'],
        );
      },
    );
  });
}

Future<void> _waitForRequests(_RecordingAdapter adapter, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (adapter.requests.length < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (adapter.requests.length < count) {
    fail('Timed out waiting for $count telemetry request(s).');
  }
}
