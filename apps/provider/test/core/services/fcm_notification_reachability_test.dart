import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';
import 'package:myshop_provider/src/core/services/local_notification_service.dart';

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

  test('notification accept does not navigate when listener already did', () {
    expect(shouldNavigateToActiveRideFromNotification('/active-ride'), isFalse);
    expect(shouldNavigateToActiveRideFromNotification('/home'), isTrue);
    expect(shouldNavigateToActiveRideFromNotification('/ride-request'), isTrue);
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

  group('incoming request tap coalescing', () {
    late IncomingRequestTapCoordinator coordinator;

    setUp(() {
      coordinator = IncomingRequestTapCoordinator();
    });

    tearDown(() {
      coordinator.dispose();
    });

    Map<String, dynamic> ridePayload({String? action}) => <String, dynamic>{
          NotificationPayload.keyType: NotificationPayload.typeRideRequest,
          NotificationPayload.keyRideId: 'ride-1',
          NotificationPayload.keyOfferId: 'offer-1',
          if (action != null) NotificationPayload.keyActionId: action,
        };

    Map<String, dynamic> jobPayload({String? action}) => <String, dynamic>{
          NotificationPayload.keyType: NotificationPayload.typeJobRequest,
          NotificationPayload.keyJobId: 'job-1',
          NotificationPayload.keyOfferId: 'job-offer-1',
          if (action != null) NotificationPayload.keyActionId: action,
        };

    test(
      'one View tap delivered three ways opens the request only once',
      () async {
        var opens = 0;

        expect(
          await coordinator.dispatch(
            ridePayload(action: NotificationPayload.actionRideView),
            () async => opens += 1,
          ),
          isTrue,
        );
        expect(
          await coordinator.dispatch(ridePayload(), () async => opens += 1),
          isFalse,
        );
        expect(
          await coordinator.dispatch(
            ridePayload(action: NotificationPayload.actionRideView),
            () async => opens += 1,
          ),
          isFalse,
        );

        expect(opens, 1);
      },
    );

    test('concurrent View callbacks share one in-flight owner', () async {
      var opens = 0;
      final entered = Completer<void>();
      final release = Completer<void>();

      final first = coordinator.dispatch(ridePayload(), () async {
        opens += 1;
        entered.complete();
        await release.future;
      });
      await entered.future;

      final second = coordinator.dispatch(
        ridePayload(action: NotificationPayload.actionRideView),
        () async => opens += 1,
      );
      final third = coordinator.dispatch(
        ridePayload(),
        () async => opens += 1,
      );

      release.complete();
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(await third, isFalse);
      expect(opens, 1);
    });

    test(
      'View does not suppress a later Accept, but Accept owns follow-ups',
      () async {
        final handled = <String>[];

        expect(
          await coordinator.dispatch(
            ridePayload(action: NotificationPayload.actionRideView),
            () async => handled.add('view'),
          ),
          isTrue,
        );
        expect(
          await coordinator.dispatch(
            ridePayload(action: NotificationPayload.actionRideAccept),
            () async => handled.add('accept'),
          ),
          isTrue,
        );
        expect(
          await coordinator.dispatch(
            ridePayload(action: NotificationPayload.actionRideAccept),
            () async => handled.add('duplicate accept'),
          ),
          isFalse,
        );
        expect(
          await coordinator.dispatch(
            ridePayload(),
            () async => handled.add('trailing view'),
          ),
          isFalse,
        );

        expect(handled, ['view', 'accept']);
      },
    );

    test('a later offer for the same ride works after the replay window',
        () async {
      coordinator.dispose();
      coordinator = IncomingRequestTapCoordinator(
        viewReplayWindow: const Duration(milliseconds: 1),
      );
      var opens = 0;
      final first = ridePayload();
      final second = <String, dynamic>{
        ...ridePayload(),
        NotificationPayload.keyOfferId: 'offer-2',
      };

      expect(await coordinator.dispatch(first, () async => opens += 1), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        await coordinator.dispatch(second, () async => opens += 1),
        isTrue,
      );

      expect(opens, 2);
    });

    test('camel, snake and nested aliases coalesce the same request', () async {
      var opens = 0;
      final canonical = ridePayload();
      final rideOnly = <String, dynamic>{
        NotificationPayload.keyType: NotificationPayload.typeRideRequest,
        'ride_id': 'ride-1',
      };
      final nestedOfferOnly = <String, dynamic>{
        'requestType': NotificationPayload.typeRideRequest,
        'data': <String, dynamic>{'offer_id': 'offer-1'},
      };

      expect(
        await coordinator.dispatch(canonical, () async => opens += 1),
        isTrue,
      );
      expect(
        await coordinator.dispatch(rideOnly, () async => opens += 1),
        isFalse,
      );
      expect(
        await coordinator.dispatch(nestedOfferOnly, () async => opens += 1),
        isFalse,
      );

      expect(opens, 1);
    });

    test(
      'learned ride and offer aliases coalesce either partial callback first',
      () async {
        coordinator.dispose();
        coordinator = IncomingRequestTapCoordinator(
          viewReplayWindow: const Duration(milliseconds: 1),
        );
        final canonical = ridePayload();
        final rideOnly = <String, dynamic>{
          NotificationPayload.keyType: NotificationPayload.typeRideRequest,
          'ride_id': 'ride-1',
        };
        final offerOnly = <String, dynamic>{
          'requestType': NotificationPayload.typeRideRequest,
          'data': <String, dynamic>{'offer_id': 'offer-1'},
        };

        // Learn the authoritative rideId ↔ offerId pair, then let its replay
        // tombstone expire so the following assertions exercise active
        // single-flight ownership rather than the short success cache.
        await coordinator.dispatch(canonical, () async {});
        await Future<void>.delayed(const Duration(milliseconds: 5));

        for (final callbacks in [
          [rideOnly, offerOnly],
          [offerOnly, rideOnly],
        ]) {
          final entered = Completer<void>();
          final release = Completer<void>();
          var opens = 0;
          final first = coordinator.dispatch(callbacks.first, () async {
            opens += 1;
            entered.complete();
            await release.future;
          });
          await entered.future;
          final duplicate = coordinator.dispatch(
            callbacks.last,
            () async => opens += 1,
          );
          release.complete();

          expect(await first, isTrue);
          expect(await duplicate, isFalse);
          expect(opens, 1);
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      },
    );

    test('unrelated notifications carrying a ride id are never coalesced',
        () async {
      var handled = 0;
      final request = ridePayload();
      final cancellation = <String, dynamic>{
        NotificationPayload.keyType: NotificationPayload.typeRideCancelled,
        NotificationPayload.keyRideId: 'ride-1',
      };
      final chat = <String, dynamic>{
        NotificationPayload.keyType: NotificationPayload.typeNewMessage,
        NotificationPayload.keyRideId: 'ride-1',
      };

      expect(
        await coordinator.dispatch(request, () async => handled += 1),
        isTrue,
      );
      expect(
        await coordinator.dispatch(cancellation, () async => handled += 1),
        isTrue,
      );
      expect(
        await coordinator.dispatch(chat, () async => handled += 1),
        isTrue,
      );

      expect(handled, 3);
    });

    test('Submit Bid is a short View action, not a terminal decision',
        () async {
      coordinator.dispose();
      coordinator = IncomingRequestTapCoordinator(
        viewReplayWindow: const Duration(milliseconds: 1),
      );
      var opens = 0;
      final payload = jobPayload(
        action: NotificationPayload.actionJobSubmitBid,
      );

      expect(
        await coordinator.dispatch(payload, () async => opens += 1),
        isTrue,
      );
      expect(
        await coordinator.dispatch(payload, () async => opens += 1),
        isFalse,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        await coordinator.dispatch(payload, () async => opens += 1),
        isTrue,
      );

      expect(opens, 2);
    });

    test('a failed loader can explicitly reopen a View retry', () async {
      var opens = 0;
      final payload = ridePayload();

      expect(
        await coordinator.dispatch(payload, () async => opens += 1),
        isTrue,
      );
      coordinator.allowViewRetry(payload);
      expect(
        await coordinator.dispatch(payload, () async => opens += 1),
        isTrue,
      );

      expect(opens, 2);
    });

    test('legacy decision fallback does not suppress a later re-offer',
        () async {
      coordinator.dispose();
      coordinator = IncomingRequestTapCoordinator(
        viewReplayWindow: const Duration(milliseconds: 1),
      );
      var decisions = 0;
      final payload = <String, dynamic>{
        NotificationPayload.keyType: NotificationPayload.typeRideRequest,
        NotificationPayload.keyRideId: 'legacy-ride',
        NotificationPayload.keyActionId: NotificationPayload.actionRideAccept,
      };

      expect(
        await coordinator.dispatch(payload, () async => decisions += 1),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        await coordinator.dispatch(payload, () async => decisions += 1),
        isTrue,
      );

      expect(decisions, 2);
    });

    test('reset prevents completed work from recreating an old-session claim',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final payload = ridePayload();

      final oldSessionTap = coordinator.dispatch(payload, () async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      coordinator.reset();
      release.complete();
      expect(await oldSessionTap, isTrue);

      var newSessionOpens = 0;
      expect(
        await coordinator.dispatch(payload, () async => newSessionOpens += 1),
        isTrue,
      );
      expect(newSessionOpens, 1);
    });

    test('Accept supersedes a View that began first', () async {
      final viewEntered = Completer<void>();
      final releaseView = Completer<void>();
      var viewNavigations = 0;
      var accepts = 0;
      final viewPayload = ridePayload();

      final view = coordinator.dispatch(viewPayload, () async {
        viewEntered.complete();
        await releaseView.future;
        if (!coordinator.shouldAbortViewAfterDecision(viewPayload)) {
          viewNavigations += 1;
        }
      });
      await viewEntered.future;

      expect(
        await coordinator.dispatch(
          ridePayload(action: NotificationPayload.actionRideAccept),
          () async => accepts += 1,
        ),
        isTrue,
      );
      releaseView.complete();
      expect(await view, isTrue);

      expect(accepts, 1);
      expect(viewNavigations, 0);
    });

    test(
      'an unexpected handler failure remains retryable until success',
      () async {
        var attempts = 0;
        final payload = ridePayload(action: NotificationPayload.actionRideView);

        await expectLater(
          coordinator.dispatch(payload, () async {
            attempts += 1;
            throw StateError('temporary failure');
          }),
          throwsStateError,
        );
        expect(
          await coordinator.dispatch(payload, () async => attempts += 1),
          isTrue,
        );
        expect(
          await coordinator.dispatch(payload, () async => attempts += 1),
          isFalse,
        );

        expect(attempts, 2);
      },
    );
  });
}
