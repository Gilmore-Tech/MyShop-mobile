import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects a server deadline onto the handset clock', () {
    final before = DateTime.now().toUtc();
    final request = ProviderPendingRequest.fromJson(
      {
        'kind': 'ride',
        'id': 'ride-1',
        'offerId': 'offer-1',
        // Deliberately far from the test handset's wall clock. The remaining
        // duration is authoritative, not either absolute local timestamp.
        'serverNow': '2020-01-01T00:00:00.000Z',
        'expiresAt': '2020-01-01T00:00:45.000Z',
      },
      transportElapsed: const Duration(seconds: 5),
    );
    final after = DateTime.now().toUtc();

    expect(request.serverExpiresAt, DateTime.utc(2020, 1, 1, 0, 0, 45));
    expect(request.expiresAt, isNotNull);
    expect(
      request.expiresAt!.difference(before),
      greaterThanOrEqualTo(const Duration(seconds: 39)),
    );
    expect(
      request.expiresAt!.difference(after),
      lessThanOrEqualTo(const Duration(seconds: 40)),
    );
    expect(request.isExpired, isFalse);
  });

  test('marks an already elapsed server window as expired despite clock skew',
      () {
    final request = ProviderPendingRequest.fromJson({
      'kind': 'ride',
      'id': 'ride-1',
      'serverNow': '2035-01-01T00:01:00.000Z',
      'expiresAt': '2035-01-01T00:00:45.000Z',
    });

    expect(request.isExpired, isTrue);
  });

  test('requests and parses exact terminal offer resolutions', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'requests': <Object>[],
                  'resolutions': [
                    {
                      'kind': 'ride',
                      'offerId': 'offer-1',
                      'rideId': 'ride-1',
                      'state': 'revoked',
                      'resolutionReason': 'cancelled_by_rider',
                      'resolvedAt': '2026-07-28T12:00:00.000Z',
                      'cancelledBy': 'client',
                    },
                    {
                      // A server response cannot make an identity actionable
                      // unless this device supplied that exact offer ID.
                      'kind': 'ride',
                      'offerId': 'foreign-offer',
                      'rideId': 'foreign-ride',
                      'state': 'revoked',
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );

    final result = await ProviderRequestService(
      dio,
    ).recoverPendingRequests(knownOfferIds: const ['offer-1']);

    expect(captured.path, '/providers/me/pending-requests');
    expect(captured.queryParameters['knownOfferIds'], 'offer-1');
    expect(result.requests, isEmpty);
    expect(result.resolutions, hasLength(1));
    expect(result.resolutions.single.offerId, 'offer-1');
    expect(result.resolutions.single.rideId, 'ride-1');
    expect(result.resolutions.single.resolutionReason, 'cancelled_by_rider');
    expect(result.resolutions.single.cancelledBy, 'client');
  });

  test('keeps the legacy requests-only response compatible', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: {
              'success': true,
              'data': {
                'requests': [
                  {'kind': 'ride', 'id': 'ride-1', 'offerId': 'offer-1'},
                ],
              },
            },
          ),
        ),
      ),
    );

    final requests = await ProviderRequestService(dio).listPendingRequests();

    expect(requests.single.id, 'ride-1');
  });

  test(
    'rejects an unbounded offer-resolution query before network I/O',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
      addTearDown(dio.close);
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.next(options);
          },
        ),
      );

      await expectLater(
        ProviderRequestService(dio).recoverPendingRequests(
          knownOfferIds: List<String>.generate(11, (index) => 'offer-$index'),
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
    },
  );
}
