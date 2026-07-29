import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const retryDelay = Duration(seconds: 1);

  test('automatically probes until readiness succeeds, then stops', () {
    fakeAsync((async) {
      var attempts = 0;
      var serviceReady = false;
      final coordinator = MobileServiceRecoveryCoordinator(
        probe: () async {
          attempts++;
          if (!serviceReady) throw StateError('offline');
        },
        delayResolver: (_) => retryDelay,
      );

      coordinator.update(recoveryNeeded: true, foreground: true);
      expect(attempts, 0);

      async.elapse(retryDelay);
      async.flushMicrotasks();
      expect(attempts, 1);

      serviceReady = true;
      async.elapse(retryDelay);
      async.flushMicrotasks();
      expect(attempts, 2);

      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(attempts, 2);
    });
  });

  test('manual retries coalesce with one readiness request in flight', () {
    fakeAsync((async) {
      var attempts = 0;
      final readiness = Completer<void>();
      final coordinator = MobileServiceRecoveryCoordinator(
        probe: () {
          attempts++;
          return readiness.future;
        },
        delayResolver: (_) => retryDelay,
      );

      coordinator.update(recoveryNeeded: true, foreground: true);
      final first = coordinator.retryNow();
      final second = coordinator.retryNow();

      expect(identical(first, second), isTrue);
      expect(attempts, 1);

      readiness.complete();
      async.flushMicrotasks();
      expect(attempts, 1);
    });
  });

  test('pauses automatic probes in background and resumes in foreground', () {
    fakeAsync((async) {
      var attempts = 0;
      final coordinator = MobileServiceRecoveryCoordinator(
        probe: () async {
          attempts++;
          throw StateError('offline');
        },
        delayResolver: (_) => retryDelay,
      );

      coordinator.update(recoveryNeeded: true, foreground: false);
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(attempts, 0);

      coordinator.update(recoveryNeeded: true, foreground: true);
      async.elapse(retryDelay);
      async.flushMicrotasks();
      expect(attempts, 1);

      coordinator.update(recoveryNeeded: true, foreground: false);
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(attempts, 1);
    });
  });

  test('dispose cancels a scheduled automatic probe', () {
    fakeAsync((async) {
      var attempts = 0;
      final coordinator = MobileServiceRecoveryCoordinator(
        probe: () async => attempts++,
        delayResolver: (_) => retryDelay,
      );

      coordinator.update(recoveryNeeded: true, foreground: true);
      coordinator.dispose();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(attempts, 0);
    });
  });

  test('default backoff remains bounded after a long outage', () {
    final delay = defaultMobileServiceRecoveryDelay(100);

    expect(delay, greaterThanOrEqualTo(const Duration(seconds: 12)));
    expect(delay, lessThanOrEqualTo(const Duration(seconds: 18)));
  });
}
