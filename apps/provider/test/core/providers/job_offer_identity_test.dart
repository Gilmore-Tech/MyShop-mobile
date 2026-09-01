import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/socket_provider.dart';

void main() {
  test('poller copy is enriched once and sequential exact offer resurfaces',
      () {
    expect(
      jobOfferSurfaceDisposition(
        jobAlreadySurfaced: true,
        lastExactOfferId: null,
        incomingOfferId: 'offer-a',
      ),
      JobOfferSurfaceDisposition.enrichExisting,
    );
    expect(
      jobOfferSurfaceDisposition(
        jobAlreadySurfaced: true,
        lastExactOfferId: 'offer-a',
        incomingOfferId: 'offer-a',
      ),
      JobOfferSurfaceDisposition.ignoreDuplicate,
    );
    expect(
      jobOfferSurfaceDisposition(
        jobAlreadySurfaced: true,
        lastExactOfferId: 'offer-a',
        incomingOfferId: 'offer-b',
      ),
      JobOfferSurfaceDisposition.surface,
    );
  });

  test('terminal offer A cannot dismiss current offer B for the same job', () {
    expect(
      jobOfferTerminalMatchesCurrent(
        currentOfferId: 'offer-b',
        terminalOfferId: 'offer-a',
      ),
      isFalse,
    );
    expect(
      jobOfferTerminalMatchesCurrent(
        currentOfferId: 'offer-b',
        terminalOfferId: 'offer-b',
      ),
      isTrue,
    );
    // Legacy invitations retain their historical job-id fallback.
    expect(
      jobOfferTerminalMatchesCurrent(
        currentOfferId: null,
        terminalOfferId: null,
      ),
      isTrue,
    );
  });

  test('late action for offer A cannot clear sequential offer B', () {
    expect(
      jobOfferActionStillOwnsCurrent(
        capturedOfferId: 'offer-a',
        currentOfferId: 'offer-b',
        lastExactOfferId: 'offer-b',
      ),
      isFalse,
    );
    expect(
      jobOfferActionStillOwnsCurrent(
        capturedOfferId: 'offer-a',
        currentOfferId: null,
        lastExactOfferId: 'offer-a',
      ),
      isTrue,
      reason:
          'a matching terminal event may remove current before REST returns',
    );
    expect(
      jobOfferActionStillOwnsCurrent(
        capturedOfferId: null,
        currentOfferId: 'offer-b',
        lastExactOfferId: 'offer-b',
      ),
      isFalse,
      reason: 'a legacy action cannot mutate a newly exact offer',
    );
  });
}
