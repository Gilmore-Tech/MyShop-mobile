import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/data/ride_booking_attempt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const firstKey = '6c466e13-466c-4bb5-82a1-b3a72728c9f1';
  const secondKey = '27706c0d-565f-489a-a2d7-b5d47bc40b78';
  final createdAt = DateTime.utc(2026, 7, 18, 10, 30);

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('canonical fingerprint ignores map order but preserves stop order', () {
    final first = rideBookingRequestFingerprint({
      'pickupLat': 5.6037,
      'pickupAddress': 'Private pickup address',
      'stops': [
        {'lat': 5.61, 'lng': -0.18},
        {'lat': 5.62, 'lng': -0.17},
      ],
    });
    final reorderedKeys = rideBookingRequestFingerprint({
      'stops': [
        {'lng': -0.18, 'lat': 5.61},
        {'lng': -0.17, 'lat': 5.62},
      ],
      'pickupAddress': 'Private pickup address',
      'pickupLat': 5.6037,
    });
    final reversedStops = rideBookingRequestFingerprint({
      'pickupLat': 5.6037,
      'pickupAddress': 'Private pickup address',
      'stops': [
        {'lat': 5.62, 'lng': -0.17},
        {'lat': 5.61, 'lng': -0.18},
      ],
    });

    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(reorderedKeys, first);
    expect(reversedStops, isNot(first));
  });

  test('persists only UUID, SHA-256 fingerprint, and timestamp', () async {
    final fingerprint = rideBookingRequestFingerprint({
      'pickupLat': 5.6037,
      'pickupLng': -0.187,
      'pickupAddress': 'Private pickup address',
      'dropoffAddress': 'Private destination address',
    });
    final store = RideBookingAttemptStore(
      bookingKeyFactory: () => firstKey,
      clock: () => createdAt,
    );

    await store.getOrCreate(fingerprint);

    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(RideBookingAttemptStore.storageKey)!;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded.keys, {
      'bookingKey',
      'requestFingerprint',
      'createdAt',
    });
    expect(decoded['bookingKey'], firstKey);
    expect(decoded['requestFingerprint'], fingerprint);
    expect(decoded['createdAt'], createdAt.toIso8601String());
    expect(raw, isNot(contains('Private pickup address')));
    expect(raw, isNot(contains('Private destination address')));
    expect(raw, isNot(contains('5.6037')));
    expect(raw, isNot(contains('-0.187')));
  });

  test('reuses one key for concurrent calls with the same fingerprint',
      () async {
    var generated = 0;
    final store = RideBookingAttemptStore(
      bookingKeyFactory: () {
        generated++;
        return firstKey;
      },
      clock: () => createdAt,
    );
    final fingerprint = rideBookingRequestFingerprint({'fare': 2500});

    final results = await Future.wait([
      store.getOrCreate(fingerprint),
      store.getOrCreate(fingerprint),
    ]);

    expect(generated, 1);
    expect(
        results.map((attempt) => attempt.bookingKey), everyElement(firstKey));
  });

  test('changed fingerprint gets a new key and clear is compare-and-delete',
      () async {
    final keys = [firstKey, secondKey].iterator;
    final store = RideBookingAttemptStore(
      bookingKeyFactory: () {
        keys.moveNext();
        return keys.current;
      },
      clock: () => createdAt,
    );
    final firstFingerprint = rideBookingRequestFingerprint({'fare': 2500});
    final secondFingerprint = rideBookingRequestFingerprint({'fare': 2600});

    final first = await store.getOrCreate(firstFingerprint);
    final second = await store.getOrCreate(secondFingerprint);
    await store.clear(bookingKey: first.bookingKey);

    expect(first.bookingKey, firstKey);
    expect(second.bookingKey, secondKey);
    expect((await store.read())?.bookingKey, secondKey);

    await store.clear(bookingKey: second.bookingKey);
    expect(await store.read(), isNull);
  });

  test('clearAll removes the persisted attempt', () async {
    final store = RideBookingAttemptStore(
      bookingKeyFactory: () => firstKey,
      clock: () => createdAt,
    );
    await store.getOrCreate(rideBookingRequestFingerprint({'fare': 2500}));

    await store.clearAll();

    expect(await store.read(), isNull);
  });
}
