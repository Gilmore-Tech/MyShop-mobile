import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/earnings/widgets/request_payout_sheet.dart';

void main() {
  test('only an identified queued payout response is authoritative', () {
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'processing', 'payoutId': 'payout-1'},
      ),
      isTrue,
    );
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'blocked_manual_review', 'payoutId': ''},
      ),
      isFalse,
    );
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'processing'},
      ),
      isFalse,
    );
    expect(
      isConfirmedQueuedPayoutResponse(
        const {'status': 'unknown', 'payoutId': 'payout-1'},
      ),
      isFalse,
    );
  });
}
