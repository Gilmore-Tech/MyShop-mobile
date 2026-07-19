import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/account_deletion_policy.dart';

void main() {
  test('provider deletion copy matches the release containment policy', () {
    expect(providerAccountDeletionNotice, contains('Only this provider role'));
    expect(providerAccountDeletionNotice, contains('Other role accounts'));
    expect(providerAccountDeletionNotice, contains('retained for 90 days'));
    expect(providerAccountDeletionNotice, contains('verify'));
    expect(providerAccountDeletionNotice, contains('contact support'));
    expect(providerAccountDeletionNotice, contains('not automatic'));
    expect(providerAccountDeletionNotice, contains('document review'));
    expect(providerAccountDeletionNotice, contains('Coordinator review'));
    expect(
        providerAccountDeletionNotice, contains('Regional Manager approval'));
    expect(providerAccountDeletionNotice, isNot(contains('24 hours')));
    expect(providerAccountDeletionNotice, isNot(contains('permanent')));
    expect(providerAccountDeletionNotice, isNot(contains('purged')));

    final visibleCopy = <String>[
      providerAccountDeactivationAccessConsequence,
      providerAccountDeactivationHistoryConsequence,
      providerAccountDeactivationVerificationConsequence,
      providerAccountDeactivationFinancialConsequence,
      providerAccountDeletionRetentionNotice,
    ].join(' ');
    expect(visibleCopy, contains('deactivated immediately'));
    expect(visibleCopy, contains('pending review'));
    expect(visibleCopy, contains('retained for 90 days'));
    expect(visibleCopy, contains('Legal holds'));
    expect(visibleCopy, contains('unsettled payments'));
    expect(visibleCopy, contains('clawbacks'));
    expect(visibleCopy, isNot(contains('450+')));
    expect(visibleCopy, isNot(contains('4.9-star')));
    expect(visibleCopy, isNot(contains('Police Clearance')));
    expect(visibleCopy, isNot(contains('full fees')));
    expect(visibleCopy, isNot(contains('7 years')));
  });
}
