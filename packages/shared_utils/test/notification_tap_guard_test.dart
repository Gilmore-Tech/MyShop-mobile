import 'dart:async';

import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  test('uses only stable routing fields and treats View as a body tap', () {
    final bodyTap = notificationTapIdentity(const {
      'notificationId': 'NOTICE-1',
      'type': 'announcement',
      'destination': 'support',
      'title': 'Private title',
      'body': 'Private body',
    });
    final viewTap = notificationTapIdentity(const {
      'notificationId': 'notice-1',
      'type': 'announcement.sent',
      'destination': 'support',
      'actionId': 'OPEN_NOTIFICATION',
    });

    expect(viewTap, bodyTap);
    expect(bodyTap, isNot(contains('Private')));
  });

  test('keeps mutating request actions distinct', () {
    final accept = notificationTapIdentity(const {
      'type': 'ride_request',
      'rideId': 'ride-1',
      'actionId': 'ACCEPT_RIDE',
    });
    final decline = notificationTapIdentity(const {
      'type': 'ride_request',
      'rideId': 'ride-1',
      'actionId': 'DECLINE_RIDE',
    });

    expect(accept, isNot(decline));
  });

  test('joins in-flight callbacks and suppresses a delayed replay', () async {
    final guard = NotificationTapGuard(
      replayWindow: const Duration(milliseconds: 20),
    );
    addTearDown(guard.dispose);
    final pending = Completer<void>();
    var calls = 0;

    final first = guard.run('notice-1', () async {
      calls += 1;
      await pending.future;
    });
    final duplicate = guard.run('notice-1', () async {
      calls += 1;
    });
    pending.complete();

    expect(await first, isTrue);
    expect(await duplicate, isFalse);
    expect(await guard.run('notice-1', () async => calls += 1), isFalse);
    expect(calls, 1);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await guard.run('notice-1', () async => calls += 1), isTrue);
    expect(calls, 2);
  });

  test('failed callbacks remain retryable', () async {
    final guard = NotificationTapGuard();
    addTearDown(guard.dispose);
    var calls = 0;

    await expectLater(
      guard.run('notice-1', () async {
        calls += 1;
        throw StateError('navigation failed');
      }),
      throwsStateError,
    );
    expect(await guard.run('notice-1', () async => calls += 1), isTrue);
    expect(calls, 2);
  });

  test('reset fences old bookkeeping while an operation is in flight',
      () async {
    final guard = NotificationTapGuard();
    addTearDown(guard.dispose);
    final pending = Completer<void>();
    var calls = 0;

    final oldOperation = guard.run('notice-1', () async {
      calls += 1;
      await pending.future;
    });
    guard.reset();
    expect(await guard.run('notice-1', () async => calls += 1), isTrue);

    pending.complete();
    expect(await oldOperation, isTrue);
    expect(calls, 2);
    expect(await guard.run('notice-1', () async => calls += 1), isFalse);
  });
}
