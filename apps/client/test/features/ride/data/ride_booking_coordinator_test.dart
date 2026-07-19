import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/data/ride_booking_attempt_store.dart';
import 'package:myshop_client/src/features/ride/data/ride_booking_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const firstKey = '6c466e13-466c-4bb5-82a1-b3a72728c9f1';
  const secondKey = '27706c0d-565f-489a-a2d7-b5d47bc40b78';
  final firstFingerprint = rideBookingRequestFingerprint({'fare': 2500});
  final changedFingerprint = rideBookingRequestFingerprint({'fare': 2600});

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  RideBookingAttemptStore makeStore([List<String>? generatedKeys]) {
    final keys = (generatedKeys ?? [firstKey, secondKey]).iterator;
    return RideBookingAttemptStore(
      bookingKeyFactory: () {
        if (!keys.moveNext()) throw StateError('No test UUID available');
        return keys.current;
      },
      clock: () => DateTime.utc(2026, 7, 18, 10, 30),
    );
  }

  test('changed request recovers an existing nonterminal ride instead of POST',
      () async {
    final store = makeStore();
    await store.getOrCreate(firstFingerprint);
    var creates = 0;
    final coordinator = RideBookingCoordinator(
      store: store,
      lookup: (key) async => {
        'rideId': 'ride-existing',
        'status': 'requested',
        'driversNotified': 1,
        'initializationPending': false,
      },
    );

    final result = await coordinator.resolveOrCreate(
      requestFingerprint: changedFingerprint,
      create: (_) async {
        creates++;
        return {'rideId': 'ride-new', 'status': 'requested'};
      },
    );

    expect(result.recovered, isTrue);
    expect(result.response['rideId'], 'ride-existing');
    expect(creates, 0);
    expect((await store.read())?.bookingKey, firstKey);
  });

  test('ambiguous lookup blocks a changed request and retains the old key',
      () async {
    final store = makeStore();
    await store.getOrCreate(firstFingerprint);
    var creates = 0;
    final coordinator = RideBookingCoordinator(
      store: store,
      lookup: (_) async => throw const NetworkException(
        message: 'No internet connection.',
      ),
    );

    await expectLater(
      coordinator.resolveOrCreate(
        requestFingerprint: changedFingerprint,
        create: (_) async {
          creates++;
          return {'rideId': 'ride-new', 'status': 'requested'};
        },
      ),
      throwsA(isA<RideBookingLookupUncertainException>()),
    );
    expect(creates, 0);
    expect((await store.read())?.bookingKey, firstKey);
  });

  test('same request reuses its key after definitive unused-key lookup',
      () async {
    final store = makeStore();
    await store.getOrCreate(firstFingerprint);
    String? postedKey;
    final coordinator = RideBookingCoordinator(
      store: store,
      lookup: (_) async => null,
    );

    final result = await coordinator.resolveOrCreate(
      requestFingerprint: firstFingerprint,
      create: (key) async {
        postedKey = key;
        return {'rideId': 'ride-new', 'status': 'requested'};
      },
    );

    expect(result.recovered, isFalse);
    expect(postedKey, firstKey);
    expect((await store.read())?.bookingKey, firstKey);
  });

  test('changed request gets a new key only after definitive unused lookup',
      () async {
    final store = makeStore();
    await store.getOrCreate(firstFingerprint);
    String? postedKey;
    final coordinator = RideBookingCoordinator(
      store: store,
      lookup: (_) async => null,
    );

    await coordinator.resolveOrCreate(
      requestFingerprint: changedFingerprint,
      create: (key) async {
        postedKey = key;
        return {'rideId': 'ride-new', 'status': 'requested'};
      },
    );

    expect(postedKey, secondKey);
    expect((await store.read())?.bookingKey, secondKey);
  });

  test('terminal lookup clears the old key before a new create', () async {
    final store = makeStore();
    await store.getOrCreate(firstFingerprint);
    String? postedKey;
    final coordinator = RideBookingCoordinator(
      store: store,
      lookup: (_) async => {'rideId': 'ride-old', 'status': 'completed'},
    );

    await coordinator.resolveOrCreate(
      requestFingerprint: firstFingerprint,
      create: (key) async {
        postedKey = key;
        return {'rideId': 'ride-new', 'status': 'requested'};
      },
    );

    expect(postedKey, secondKey);
    expect((await store.read())?.bookingKey, secondKey);
  });

  test('network, 5xx, and 409 create failures retain the key', () async {
    final errors = <ApiException>[
      const NetworkException(message: 'Connection lost.'),
      const ServerException(message: 'Unavailable.', statusCode: 503),
      const ConflictException(
        message: 'Conflict.',
        errorCode: 'BOOKING_ATTEMPT_CONFLICT',
      ),
    ];

    for (final error in errors) {
      SharedPreferences.setMockInitialValues(const {});
      final store = makeStore([firstKey]);
      final coordinator = RideBookingCoordinator(
        store: store,
        lookup: (_) async => null,
      );

      await expectLater(
        coordinator.resolveOrCreate(
          requestFingerprint: firstFingerprint,
          create: (_) async => throw error,
        ),
        throwsA(same(error)),
      );
      expect((await store.read())?.bookingKey, firstKey);
    }
  });

  test('definitive pre-create 422 clears the key', () async {
    final store = makeStore([firstKey]);
    final coordinator = RideBookingCoordinator(
      store: store,
      lookup: (_) async => null,
    );

    await expectLater(
      coordinator.resolveOrCreate(
        requestFingerprint: firstFingerprint,
        create: (_) async => throw const ValidationException(
          message: 'Invalid request.',
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(await store.read(), isNull);
  });

  test('concurrent calls share one lookup/create operation', () async {
    final store = makeStore([firstKey]);
    final createResult = Completer<Map<String, dynamic>>();
    var creates = 0;
    final coordinator = RideBookingCoordinator(
      store: store,
      lookup: (_) async => null,
    );

    final first = coordinator.resolveOrCreate(
      requestFingerprint: firstFingerprint,
      create: (_) {
        creates++;
        return createResult.future;
      },
    );
    final second = coordinator.resolveOrCreate(
      requestFingerprint: changedFingerprint,
      create: (_) async => {'rideId': 'duplicate', 'status': 'requested'},
    );
    await Future<void>.delayed(Duration.zero);
    createResult.complete({'rideId': 'ride-one', 'status': 'requested'});

    final results = await Future.wait([first, second]);
    expect(creates, 1);
    expect(results.map((result) => result.response['rideId']),
        everyElement('ride-one'));
  });
}
