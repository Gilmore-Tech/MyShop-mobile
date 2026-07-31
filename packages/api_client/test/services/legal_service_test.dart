import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioFor(String body) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
  dio.httpClientAdapter = _JsonAdapter(body);
  return dio;
}

void main() {
  test('accepts an explicit, typed legal-consent status', () async {
    final dio = _dioFor(
      '{"success":true,"data":{"role":"client","current":true,'
      '"requiresConsent":false,"hasActiveWork":false,'
      '"missingSlugs":[],"documents":[]}}',
    );
    addTearDown(dio.close);

    final status = await LegalService(dio).getConsentStatus();

    expect(status.role, 'client');
    expect(status.requiresConsent, isFalse);
  });

  test(
    'missing requiresConsent is unavailable rather than inferred true',
    () async {
      final dio = _dioFor(
        '{"success":true,"data":{"role":"client","current":false,'
        '"hasActiveWork":false,"missingSlugs":[],"documents":[]}}',
      );
      addTearDown(dio.close);

      await expectLater(
        LegalService(dio).getConsentStatus(),
        throwsA(
          isA<NetworkException>()
              .having(
                (error) => error.kind,
                'kind',
                NetworkFailureKind.unavailable,
              )
              .having(
                (error) => error.message,
                'safe message',
                'Service temporarily unavailable. Please try again in a moment.',
              ),
        ),
      );
    },
  );

  test(
    'wrongly typed or unknown-role status cannot drive navigation',
    () async {
      final dio = _dioFor(
        '{"success":true,"data":{"role":"admin","current":false,'
        '"requiresConsent":"yes","hasActiveWork":false,'
        '"missingSlugs":[],"documents":[]}}',
      );
      addTearDown(dio.close);

      await expectLater(
        LegalService(dio).getConsentStatus(),
        throwsA(
          isA<NetworkException>().having(
            (error) => error.kind,
            'kind',
            NetworkFailureKind.unavailable,
          ),
        ),
      );
    },
  );

  test('malformed legal document entries are service-unavailable', () async {
    final dio = _dioFor(
      '{"success":true,"data":{"role":"client","current":false,'
      '"requiresConsent":true,"hasActiveWork":false,'
      '"missingSlugs":["terms"],"documents":["raw internal payload"]}}',
    );
    addTearDown(dio.close);

    await expectLater(
      LegalService(dio).getConsentStatus(),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.kind,
          'kind',
          NetworkFailureKind.unavailable,
        ),
      ),
    );
  });
}
