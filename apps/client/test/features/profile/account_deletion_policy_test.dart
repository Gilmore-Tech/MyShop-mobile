import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/profile/account_deletion_policy.dart';

void main() {
  test('client deletion copy matches the release containment policy', () {
    expect(clientAccountDeletionNotice, contains('Only your client account'));
    expect(clientAccountDeletionNotice, contains('Other role accounts'));
    expect(clientAccountDeletionNotice, contains('retained for 90 days'));
    expect(clientAccountDeletionNotice, contains('verify'));
    expect(clientAccountDeletionNotice, contains('contact support'));
    expect(clientAccountDeletionNotice, contains('not automatic'));
    expect(clientAccountDeletionNotice, contains('Operations approval'));
    expect(clientAccountDeletionNotice, isNot(contains('24 hours')));
    expect(clientAccountDeletionNotice, isNot(contains('permanent')));
    expect(clientAccountDeletionNotice, isNot(contains('purged')));
  });
}
