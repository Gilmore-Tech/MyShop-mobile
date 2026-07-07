import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  Dio dioReturning(Object? value) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'key': 'ride_multistop_pretrip_enabled',
                  'value': value,
                },
              },
            ),
          );
        },
      ),
    );
    return dio;
  }

  test('getBoolean parses true-ish values', () async {
    expect(
      await PlatformConfigService(dioReturning('true'))
          .getBoolean('ride_multistop_pretrip_enabled'),
      isTrue,
    );
    expect(
      await PlatformConfigService(dioReturning('1'))
          .getBoolean('ride_multistop_pretrip_enabled'),
      isTrue,
    );
  });

  test('getBoolean parses false-ish values', () async {
    expect(
      await PlatformConfigService(dioReturning('false'))
          .getBoolean('ride_multistop_pretrip_enabled'),
      isFalse,
    );
    expect(
      await PlatformConfigService(dioReturning('0'))
          .getBoolean('ride_multistop_pretrip_enabled'),
      isFalse,
    );
  });

  test('getBoolean returns null for invalid values', () async {
    expect(
      await PlatformConfigService(dioReturning('later'))
          .getBoolean('ride_multistop_pretrip_enabled'),
      isNull,
    );
  });
}
