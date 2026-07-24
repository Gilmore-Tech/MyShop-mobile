import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release UI and privacy manifest contain manual v1 verification', () {
    final source = <String>[
      File('lib/src/features/onboarding/screens/onboarding_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/onboarding/screens/role_picker_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/profile/screens/account_settings_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/artisan_home/screens/active_job_screen.dart')
          .readAsStringSync(),
      File('lib/src/features/profile/screens/documents_verification_screen.dart')
          .readAsStringSync(),
      File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync(),
    ].join('\n');

    expect(source, contains('Manual document review'));
    expect(source, contains('Regional Manager review'));
    expect(source, isNot(contains('Instant MoMo payouts')));
    expect(source, isNot(contains('get paid instantly')));
    expect(source, isNot(contains('Background checks')));
    expect(source, isNot(contains('24/7 support')));
    expect(source, isNot(contains('Police Check')));
    expect(source, isNot(contains('24-48 hours')));
    expect(source,
        isNot(contains('reviewed by our compliance team within 24 hours')));
    expect(source, isNot(contains('NSPrivacyCollectedDataTypeSensitiveInfo')));
    expect(source, isNot(contains('paid the moment')));
    expect(source, isNot(contains('released to your wallet')));
    expect(source, contains('one driver and one artisan account'));
  });
}
