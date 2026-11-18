import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions request;
  Object? value;

  setUp(() {
    value = 12.5;
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          request = options;
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'success': true,
                'data': {'key': 'commission_rate_percent', 'value': value},
              },
            ),
          );
        },
      ),
    );
  });

  tearDown(() => dio.close(force: true));

  test('getBoolean parses true-ish values', () async {
    final config = PlatformConfigService(dio);
    for (final candidate in ['true', '1']) {
      value = candidate;
      expect(await config.getBoolean('ride_multistop_pretrip_enabled'), isTrue);
    }
  });

  test('getBoolean parses false-ish values', () async {
    final config = PlatformConfigService(dio);
    for (final candidate in ['false', '0']) {
      value = candidate;
      expect(
        await config.getBoolean('ride_multistop_pretrip_enabled'),
        isFalse,
      );
    }
  });

  test('getBoolean returns null for invalid values', () async {
    value = 'later';
    expect(
      await PlatformConfigService(dio)
          .getBoolean('ride_multistop_pretrip_enabled'),
      isNull,
    );
  });

  test('reads the effective commission for the booking region', () async {
    final config = PlatformConfigService(dio);
    expect(
      await config.getNumber('commission_rate_percent', regionId: 'bono'),
      12.5,
    );
    expect(request.path, '/config/commission_rate_percent');
    expect(request.queryParameters, {'regionId': 'bono'});
  });

  test('preserves global reads when no region is supplied', () async {
    expect(
      await PlatformConfigService(dio).getNumber('commission_rate_percent'),
      12.5,
    );
    expect(request.queryParameters, isEmpty);
  });

  test('supports zero commission and does not invent a missing rate', () async {
    final config = PlatformConfigService(dio);
    value = 0;
    expect(
      await config.getNumber('commission_rate_percent', regionId: 'bono'),
      0,
    );
    value = null;
    expect(
      await config.getNumber('commission_rate_percent', regionId: 'bono'),
      isNull,
    );
  });
}
