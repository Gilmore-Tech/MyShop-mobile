import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/ride_offer_receipt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const rideId = '11111111-1111-4111-8111-111111111111';
  const offerId = '22222222-2222-4222-8222-222222222222';
  final now = DateTime.parse('2026-07-17T12:00:04.000Z');
  final deadline = DateTime.parse('2026-07-17T12:00:49.000Z');

  Map<String, dynamic> delivery() => {
        'rideId': rideId,
        'offerId': offerId,
        'offerVersion': '2',
        'deliveryExpiresAt': '2026-07-17T12:00:10.000Z',
        'pickupAddress': 'Adum',
        'offerPayload': '{"estimatedFarePesewas":2500,"distanceKm":4.2}',
      };

  test('recognises only a complete version 2 receipt envelope', () {
    expect(isReceiptRideOffer(delivery()), isTrue);
    expect(
      isReceiptRideOffer({...delivery()}..remove('offerId')),
      isFalse,
    );
    expect(
      isReceiptRideOffer({...delivery(), 'offerVersion': '1'}),
      isFalse,
    );
  });

  test('uses the exact server decision deadline and merges safe push details',
      () {
    final received = buildReceivedRideOfferForTesting(
      delivery: delivery(),
      receipt: {
        'offerId': offerId,
        'rideId': rideId,
        'decisionExpiresAt': deadline.toIso8601String(),
        'acceptanceWindowSeconds': 45,
      },
      now: now,
    );

    expect(received, isNotNull);
    expect(received!.offerId, offerId);
    expect(received.rideId, rideId);
    expect(received.decisionExpiresAt, deadline);
    expect(received.payload['expiresAt'], deadline.toIso8601String());
    expect(received.payload['acceptanceExpiresAt'], deadline.toIso8601String());
    expect(received.payload['estimatedFarePesewas'], 2500);
    expect(received.payload['distanceKm'], 4.2);
    expect(received.payload['pickupAddress'], 'Adum');
  });

  test('rejects an already-expired server decision deadline', () {
    final received = buildReceivedRideOfferForTesting(
      delivery: delivery(),
      receipt: {
        'decisionExpiresAt': '2026-07-17T12:00:03.999Z',
      },
      now: now,
    );

    expect(received, isNull);
  });

  test('uses server remaining time when the handset wall clock is wrong', () {
    final skewedHandsetNow = DateTime.parse('2099-01-01T00:00:00.000Z');
    final received = buildReceivedRideOfferForTesting(
      delivery: delivery(),
      receipt: {
        'decisionExpiresAt': deadline.toIso8601String(),
        'serverNow': now.toIso8601String(),
        'acceptanceWindowSeconds': 45,
      },
      now: skewedHandsetNow,
      transportElapsed: const Duration(seconds: 2),
    );

    final localDeadline = skewedHandsetNow.add(const Duration(seconds: 43));
    expect(received, isNotNull);
    expect(received!.decisionExpiresAt, localDeadline);
    expect(received.payload['expiresAt'], localDeadline.toIso8601String());
    expect(
      received.payload['serverDecisionExpiresAt'],
      deadline.toIso8601String(),
    );
  });

  test('rejects a receipt whose server-authoritative remaining time elapsed',
      () {
    final received = buildReceivedRideOfferForTesting(
      delivery: delivery(),
      receipt: {
        'decisionExpiresAt': deadline.toIso8601String(),
        'serverNow': deadline.toIso8601String(),
      },
      now: DateTime.parse('1999-01-01T00:00:00.000Z'),
    );

    expect(received, isNull);
  });

  test('rejects malformed receipt data instead of inventing a deadline', () {
    expect(
      buildReceivedRideOfferForTesting(
        delivery: delivery(),
        receipt: const {'state': 'active'},
        now: now,
      ),
      isNull,
    );
  });

  test('durable handoff stores identity and deadlines without request PII',
      () async {
    SharedPreferences.setMockInitialValues({});
    final payload = {
      ...delivery(),
      'pickupLatitude': 6.68,
      'pickupLongitude': -1.62,
      'clientName': 'Ama Client',
      'shareToken': 'secret-share-token',
    };

    expect(await persistIncomingRideOffer(payload), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    final stored = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    expect(stored['rideId'], rideId);
    expect(stored['offerId'], offerId);
    expect(stored['deliveryExpiresAt'], '2026-07-17T12:00:10.000Z');
    expect(stored, isNot(contains('pickupLatitude')));
    expect(stored, isNot(contains('pickupLongitude')));
    expect(stored, isNot(contains('clientName')));
    expect(stored, isNot(contains('shareToken')));
  });
}
