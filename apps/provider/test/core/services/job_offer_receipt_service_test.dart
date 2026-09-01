import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/job_offer_receipt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const jobId = '11111111-1111-4111-8111-111111111111';
  const offerId = '22222222-2222-4222-8222-222222222222';
  final now = DateTime.parse('2026-08-31T12:00:00.000Z');
  final deadline = DateTime.parse('2026-08-31T12:00:45.000Z');

  Map<String, dynamic> delivery() => {
        'type': 'job_request',
        'jobId': jobId,
        'offerId': offerId,
        'offerVersion': '2',
        'deliveryExpiresAt': '2026-08-31T12:00:10.000Z',
        'offerPayload': jsonEncode({
          'status': 'open',
          'categoryId': 'plumbing',
          'description': 'Repair a tap',
          'latitude': 5.6,
          'longitude': -0.2,
        }),
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetJobOfferReceiptMemoryForTesting();
  });

  test('recognises only a complete version-2 job receipt envelope', () {
    expect(isReceiptJobOffer(delivery()), isTrue);
    expect(isReceiptJobOffer({...delivery()}..remove('offerId')), isFalse);
    expect(
      isReceiptJobOffer({...delivery(), 'offerVersion': '1'}),
      isFalse,
    );
  });

  test('uses server remaining time and merges privacy-safe job details', () {
    final received = buildReceivedJobOfferForTesting(
      delivery: delivery(),
      receipt: {
        'jobId': jobId,
        'offerId': offerId,
        'state': 'active',
        'serverNow': now.toIso8601String(),
        'decisionExpiresAt': deadline.toIso8601String(),
        'responseWindowSeconds': 45,
      },
      now: DateTime.parse('2099-01-01T00:00:00.000Z'),
      transportElapsed: const Duration(seconds: 2),
    );

    expect(received, isNotNull);
    expect(received!.jobId, jobId);
    expect(received.offerId, offerId);
    expect(
      received.decisionExpiresAt,
      DateTime.parse('2099-01-01T00:00:45.000Z'),
    );
    expect(received.payload['status'], 'open');
    expect(received.payload['description'], 'Repair a tap');
  });

  test('accepts a directed-quote deadline from the receipt', () {
    final received = buildReceivedJobOfferForTesting(
      delivery: {
        ...delivery(),
        'type': 'job_manually_assigned',
        'mode': 'request_quote',
      },
      receipt: {
        'jobId': jobId,
        'offerId': offerId,
        'state': 'active',
        'serverNow': now.toIso8601String(),
        'quoteDeadlineAt': deadline.toIso8601String(),
        'responseWindowSeconds': 45,
      },
      now: now,
    );

    expect(received?.decisionExpiresAt, deadline);
  });

  test('rejects a mismatched or malformed server receipt', () {
    expect(
      buildReceivedJobOfferForTesting(
        delivery: delivery(),
        receipt: {
          'jobId': jobId,
          'offerId': 'different-offer',
          'state': 'active',
          'decisionExpiresAt': deadline.toIso8601String(),
        },
        now: now,
      ),
      isNull,
    );
    expect(
      buildReceivedJobOfferForTesting(
        delivery: delivery(),
        receipt: {
          'jobId': jobId,
          'offerId': offerId,
          'state': 'expired',
          'decisionExpiresAt': deadline.toIso8601String(),
        },
        now: now,
      ),
      isNull,
    );
  });

  test('legacy offers stay compatible without inventing an offer identity',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    var requestCount = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestCount++;
          handler.next(options);
        },
      ),
    );

    final received = await acknowledgeJobOffer(
      payload: const {
        'jobId': jobId,
        'status': 'open',
      },
      jobs: JobService(dio),
    );

    expect(received, isNotNull);
    expect(received!.hasExactReceipt, isFalse);
    expect(requestCount, 0);
    expect(await readStoredJobOfferIdentities(), isEmpty);
  });

  test('concurrent delivery copies share one exact authenticated receipt',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    var requestCount = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requestCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'jobId': jobId,
                  'offerId': offerId,
                  'state': 'active',
                  'serverNow': DateTime.now().toUtc().toIso8601String(),
                  'decisionExpiresAt': DateTime.now()
                      .toUtc()
                      .add(const Duration(seconds: 45))
                      .toIso8601String(),
                  'responseWindowSeconds': 45,
                },
              },
            ),
          );
        },
      ),
    );
    final jobs = JobService(dio);

    final results = await Future.wait([
      acknowledgeJobOffer(payload: delivery(), jobs: jobs),
      acknowledgeJobOffer(payload: delivery(), jobs: jobs),
    ]);

    expect(requestCount, 1);
    expect(results.every((result) => result?.offerId == offerId), isTrue);
    expect(await readStoredJobOfferIdentities(), hasLength(1));
  });

  test('durable handoff stores no client or job PII', () async {
    final payload = {
      ...delivery(),
      'clientName': 'Ama Client',
      'addressText': 'Private address',
      'photos': ['https://private.example/photo.jpg'],
    };

    expect(await persistIncomingJobOffer(payload), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(prefs.getKeys().single)!)
        as Map<String, dynamic>;
    expect(stored['jobId'], jobId);
    expect(stored['offerId'], offerId);
    expect(stored, isNot(contains('clientName')));
    expect(stored, isNot(contains('addressText')));
    expect(stored, isNot(contains('photos')));
    expect(stored, isNot(contains('offerPayload')));
  });

  test('account purge fences a receipt that completes after logout', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    addTearDown(dio.close);
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requestStarted.complete();
          await releaseResponse.future;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'jobId': jobId,
                  'offerId': offerId,
                  'state': 'active',
                  'serverNow': now.toIso8601String(),
                  'decisionExpiresAt': deadline.toIso8601String(),
                },
              },
            ),
          );
        },
      ),
    );

    final pending = acknowledgeJobOffer(
      payload: delivery(),
      jobs: JobService(dio),
    );
    await requestStarted.future;
    await purgeStoredJobOffers();
    releaseResponse.complete();

    expect(await pending, isNull);
    expect(await readStoredJobOfferIdentities(), isEmpty);
  });
}
