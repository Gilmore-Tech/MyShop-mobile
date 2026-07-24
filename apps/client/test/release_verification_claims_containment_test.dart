import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release UI makes only the approved manual verification claims', () {
    final source = <String>[
      File('lib/src/features/home/widgets/safety_banner.dart')
          .readAsStringSync(),
      File('lib/src/features/ride/widgets/driver_profile_header.dart')
          .readAsStringSync(),
      File('lib/src/features/services/screens/job_summary_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/services/screens/active_job_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/services/screens/job_complete_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/profile/widgets/submit_ghana_card_sheet.dart')
          .readAsStringSync(),
      File('lib/src/features/profile/screens/privacy_security_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/ride/screens/ride_dispute_screen.dart')
          .readAsStringSync(),
    ].join('\n');

    expect(source, contains('Regional Manager approval'));
    expect(source, contains('RM Approved'));
    expect(source, isNot(contains('Police Checked')));
    expect(source, isNot(contains('Ghana Police & KYC')));
    expect(source, isNot(contains('highly-rated driver')));
    expect(source, isNot(contains('Kumasi Central Market')));
    expect(source, isNot(contains('Instant Payout Successful')));
    expect(source, isNot(contains('Funds arrived')));
    expect(source, isNot(contains('Payment released to')));
    expect(source, isNot(contains('Payment released from escrow')));
    expect(source, isNot(contains('3-hour safe period')));
    expect(source, isNot(contains('available for 48 hours')));
    expect(source, isNot(contains('verified against national databases')));
    expect(source, isNot(contains('higher transaction limits')));
    expect(source, isNot(contains('review your submission within 24 hours')));
    expect(source, isNot(contains('completes within 24 hours')));
    expect(source, isNot(contains('will respond within 24 hours')));
    expect(source, contains('within 24 hours'));
  });
}
