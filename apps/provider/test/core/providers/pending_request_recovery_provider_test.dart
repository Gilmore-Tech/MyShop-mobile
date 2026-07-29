import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/pending_request_recovery_provider.dart';
import 'package:myshop_provider/src/core/services/ride_offer_receipt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flushAsyncWork() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final reconnectSecond in const [1, 2, 3, 4]) {
    test(
      'queues a reconnect at ${reconnectSecond}s for the remaining cooldown',
      () async {
        final startedAt = DateTime.utc(2026, 7, 28, 12);
        var now = startedAt;
        var recoveries = 0;
        final delays = <Duration>[];
        final delayCompleters = <Completer<void>>[];
        final scheduler = PendingRequestRecoveryScheduler(
          now: () => now,
          delay: (duration) {
            delays.add(duration);
            final completer = Completer<void>();
            delayCompleters.add(completer);
            return completer.future;
          },
        );

        scheduler.schedule(() async => recoveries++);
        await _flushAsyncWork();
        expect(recoveries, 1);

        now = startedAt.add(Duration(seconds: reconnectSecond));
        scheduler.schedule(() async => recoveries++);
        await _flushAsyncWork();

        expect(recoveries, 1);
        expect(delays, [Duration(seconds: 5 - reconnectSecond)]);

        now = startedAt.add(const Duration(seconds: 5));
        delayCompleters.single.complete();
        await _flushAsyncWork();

        expect(recoveries, 2);
        expect(delays, hasLength(1));
      },
    );
  }

  test('coalesces repeated reconnect triggers into one delayed recovery',
      () async {
    final startedAt = DateTime.utc(2026, 7, 28, 12);
    var now = startedAt;
    var recoveries = 0;
    final delays = <Duration>[];
    final delayCompleter = Completer<void>();
    final scheduler = PendingRequestRecoveryScheduler(
      now: () => now,
      delay: (duration) {
        delays.add(duration);
        return delayCompleter.future;
      },
    );

    scheduler.schedule(() async => recoveries++);
    await _flushAsyncWork();
    expect(recoveries, 1);

    for (final second in const [1, 2, 3, 4]) {
      now = startedAt.add(Duration(seconds: second));
      scheduler.schedule(() async => recoveries++);
    }
    await _flushAsyncWork();

    expect(delays, [const Duration(seconds: 4)]);
    expect(recoveries, 1);

    now = startedAt.add(const Duration(seconds: 5));
    delayCompleter.complete();
    await _flushAsyncWork();

    expect(recoveries, 2);
    expect(delays, hasLength(1));
  });

  test('transient recovery failure retains every stored exact offer ID',
      () async {
    const rideId = '11111111-1111-4111-8111-111111111111';
    const offerId = '22222222-2222-4222-8222-222222222222';
    SharedPreferences.setMockInitialValues({});
    expect(
      await persistIncomingRideOffer(const {
        'offerVersion': 2,
        'rideId': rideId,
        'offerId': offerId,
      }),
      isTrue,
    );
    List<String>? attemptedIds;

    final recovery = await fetchProviderRequestRecovery(
      readStoredOffers: readStoredRideOfferIdentities,
      recover: (knownOfferIds) async {
        attemptedIds = knownOfferIds;
        throw const NetworkException(
          message: 'offline',
          kind: NetworkFailureKind.offline,
        );
      },
    );

    expect(recovery, isNull);
    expect(attemptedIds, [offerId]);
    expect(
      (await readStoredRideOfferIdentities())
          .map((identity) => identity.offerId),
      [offerId],
    );
  });

  test(
      'consumes every exact tombstone once and surfaces fixed cancellation copy',
      () async {
    const resolutions = [
      ProviderRequestResolution(
        kind: ProviderRequestKind.ride,
        offerId: 'offer-1',
        rideId: 'ride-1',
        state: 'revoked',
        resolutionReason: 'cancelled_by_rider',
        cancelledBy: 'client',
      ),
      ProviderRequestResolution(
        kind: ProviderRequestKind.ride,
        offerId: 'offer-2',
        rideId: 'ride-2',
        state: 'revoked',
        resolutionReason: 'cancelled_by_admin',
        cancelledBy: 'admin',
      ),
    ];
    final dismissed = <String>[];
    final consumed = <String>[];
    final notices = <String>[];

    await consumeProviderRideOfferResolutions(
      resolutions: resolutions,
      dismiss: (resolution) => dismissed.add(resolution.rideId),
      consume: (resolution) async => consumed.add(resolution.offerId),
      claimNotice: (_) => true,
      showNotice: notices.add,
    );

    expect(dismissed, ['ride-1', 'ride-2']);
    expect(consumed, ['offer-1', 'offer-2']);
    expect(notices, ['The rider cancelled this ride request.']);
  });

  test('live-delivery dedupe suppresses only the repeated notice, not cleanup',
      () async {
    const resolution = ProviderRequestResolution(
      kind: ProviderRequestKind.ride,
      offerId: 'offer-1',
      rideId: 'ride-1',
      state: 'revoked',
      resolutionReason: 'cancelled_by_rider',
      cancelledBy: 'client',
    );
    var consumed = 0;
    var dismissed = 0;
    var notices = 0;

    await consumeProviderRideOfferResolutions(
      resolutions: const [resolution],
      dismiss: (_) => dismissed++,
      consume: (_) async => consumed++,
      claimNotice: (_) => false,
      showNotice: (_) => notices++,
    );

    expect(dismissed, 1);
    expect(consumed, 1);
    expect(notices, 0);
  });

  test('an exact rider tombstone is not eligible for generic empty-list dismissal',
      () {
    expect(
      shouldApplyGenericPendingRideDismissal(
        visibleRideId: 'ride-1',
        resolvedRideIds: const {'ride-1'},
      ),
      isFalse,
    );
    expect(
      shouldApplyGenericPendingRideDismissal(
        visibleRideId: 'ride-2',
        resolvedRideIds: const {'ride-1'},
      ),
      isTrue,
    );
  });
}
