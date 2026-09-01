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
      greaterThanOrEqualTo(const Duration(seconds: 44)),
    );
    expect(
      request.expiresAt!.difference(after),
      lessThanOrEqualTo(const Duration(seconds: 45)),
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

  test('reads an exact job offer id from its legacy nested payload', () {
    final request = ProviderPendingRequest.fromJson(const {
      'kind': 'job',
      'id': 'job-1',
      'expiresAt': '2099-01-01T00:00:45.000Z',
      'payload': {
        'jobId': 'job-1',
        'offerId': 'job-offer-1',
        'status': 'open',
      },
    });

    expect(request.offerId, 'job-offer-1');
    expect(request.offerVersion, isNull);
  });

  test('reads the exact job receipt protocol version from nested payload', () {
    final request = ProviderPendingRequest.fromJson(const {
      'kind': 'job',
      'id': 'job-1',
      'expiresAt': '2099-01-01T00:00:45.000Z',
      'payload': {
        'jobId': 'job-1',
        'offerId': 'job-offer-1',
        'offerVersion': '2',
        'status': 'open',
      },
    });

    expect(request.offerVersion, 2);
  });

  test('parses an exact terminal job-offer resolution', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: const {
              'success': true,
              'data': {
                'requests': <Object>[],
                'resolutions': [
                  {
                    'kind': 'job',
                    'offerId': 'job-offer-1',
                    'jobId': 'job-1',
                    'state': 'timed_out',
                    'resolutionReason': 'no_response',
                    'resolvedAt': '2026-08-31T12:00:45.000Z',
                  },
                ],
              },
            },
          ),
        ),
      ),
    );

    final result = await ProviderRequestService(dio).recoverPendingRequests(
      knownOfferIds: const ['job-offer-1'],
    );

    expect(result.resolutions, hasLength(1));
    expect(result.resolutions.single.kind, ProviderRequestKind.job);
    expect(result.resolutions.single.jobId, 'job-1');
    expect(result.resolutions.single.rideId, isEmpty);
    expect(result.resolutions.single.resolutionReason, 'no_response');
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
          knownOfferIds: List<String>.generate(
            maxKnownProviderOfferIds + 1,
            (index) => 'offer-$index',
          ),
        ),
        throwsArgumentError,
      );
      expect(requests, 0);
    },
  );

  test('parses authoritative response metrics and an active restriction',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: const {
              'success': true,
              'data': {
                'periodDays': 7,
                'eligibleOffers': 10,
                'acceptedOffers': 6,
                'declinedOffers': 2,
                'noResponseOffers': 2,
                'acceptanceRatePercent': 60,
                'responseRatePercent': 80,
                'activeRestriction': {
                  'policyKind': 'request_response',
                  'blockedUntil': '2026-08-31T12:15:00.000Z',
                  'retryAfterSeconds': 900,
                  'points': 6,
                  'threshold': 6,
                },
              },
            },
          ),
        ),
      ),
    );

    final summary =
        await ProviderRequestService(dio).getRequestResponseSummary();

    expect(summary, isNotNull);
    expect(summary!.periodDays, 7);
    expect(summary.eligibleOffers, 10);
    expect(summary.acceptanceRatePercent, 60);
    expect(summary.responseRatePercent, 80);
    expect(summary.activeRestriction?.policyKind, 'request_response');
    expect(summary.activeRestriction?.points, 6);
  });

  test('missing summary fields stay neutral instead of inventing a rate', () {
    final summary = ProviderRequestResponseSummary.fromJson(const {});

    expect(summary.hasSample, isFalse);
    expect(summary.acceptanceRatePercent, isNull);
    expect(summary.responseRatePercent, isNull);
    expect(summary.activeRestriction, isNull);
  });

  test('summary endpoint returns null against an older 404 backend', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response<void>(requestOptions: options, statusCode: 404),
            type: DioExceptionType.badResponse,
          ),
        ),
      ),
    );

    expect(
      await ProviderRequestService(dio).getRequestResponseSummary(),
      isNull,
    );
  });
}
