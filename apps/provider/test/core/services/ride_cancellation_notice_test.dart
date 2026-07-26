import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/ride_cancellation_notice.dart';

void main() {
  setUp(resetRiderCancellationNoticeDedupe);

  test('recognises only rider cancellation revocations', () {
    expect(isRiderCancellationRevocation('cancelled_by_rider'), isTrue);
    expect(isRiderCancellationRevocation(' CANCELLED_BY_RIDER '), isTrue);
    expect(isRiderCancellationRevocation('accepted_elsewhere'), isFalse);
    expect(isRiderCancellationRevocation(null), isFalse);
  });

  test('deduplicates socket and foreground push notices for one ride', () {
    expect(claimRiderCancellationInAppNotice('ride-1'), isTrue);
    expect(claimRiderCancellationInAppNotice('ride-1'), isFalse);
    expect(claimRiderCancellationInAppNotice('ride-2'), isTrue);
  });
}
