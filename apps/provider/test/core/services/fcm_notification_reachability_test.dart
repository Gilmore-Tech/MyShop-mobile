import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';

void main() {
  test('authorized and provisional notification access can go online', () {
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.authorized),
      isTrue,
    );
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.provisional),
      isTrue,
    );
  });

  test('denied and undetermined notification access cannot go online', () {
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.denied),
      isFalse,
    );
    expect(
      notificationAuthorizationAllowsOnline(AuthorizationStatus.notDetermined),
      isFalse,
    );
  });

  group('ride request notification navigation', () {
    test('fallback is bounded just beyond the ten-second hydrate timeout', () {
      expect(
        rideRequestNavigationFallbackDuration,
        const Duration(seconds: 12),
      );
    });

    test('an old loader cannot release a newer same-ride navigation latch', () {
      final oldToken = Object();
      final newToken = Object();
      final tokens = <String, Object>{'ride-1': newToken};
      var releaseCount = 0;

      expect(
        releaseRideRequestNavigationLatchIfOwned(
          latchTokens: tokens,
          rideId: 'ride-1',
          token: oldToken,
          onRelease: () => releaseCount += 1,
        ),
        isFalse,
      );
      expect(tokens['ride-1'], same(newToken));
      expect(releaseCount, 0);

      expect(
        releaseRideRequestNavigationLatchIfOwned(
          latchTokens: tokens,
          rideId: 'ride-1',
          token: newToken,
          onRelease: () => releaseCount += 1,
        ),
        isTrue,
      );
      expect(tokens, isEmpty);
      expect(releaseCount, 1);
    });

    test('suppresses a duplicate while the same request is hydrating', () {
      expect(
        rideRequestNavigationAlreadyActive(
          rideId: 'ride-1',
          visibleRideId: null,
          navigationInFlightRideIds: const {'ride-1'},
        ),
        isTrue,
      );
    });

    test('suppresses a duplicate when the same request is visible', () {
      expect(
        rideRequestNavigationAlreadyActive(
          rideId: 'ride-1',
          visibleRideId: 'ride-1',
          navigationInFlightRideIds: const {},
        ),
        isTrue,
      );
    });

    test('allows navigation for a different request', () {
      expect(
        rideRequestNavigationAlreadyActive(
          rideId: 'ride-2',
          visibleRideId: 'ride-1',
          navigationInFlightRideIds: const {'ride-3'},
        ),
        isFalse,
      );
    });
  });
}
