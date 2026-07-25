import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/deep_links/referral_deep_link.dart';

void main() {
  group('parseReferralCode', () {
    test('accepts approved custom-scheme shapes and normalizes case', () {
      expect(
        parseReferralCode(
          Uri.parse('myshop://referral?code=myshop-ab12cd'),
        ),
        'MYSHOP-AB12CD',
      );
      expect(
        parseReferralCode(Uri.parse('myshop://refer/MYSHOP-9Z8Y7X')),
        'MYSHOP-9Z8Y7X',
      );
    });

    test('rejects non-MyShop links and malformed codes', () {
      expect(
        parseReferralCode(
          Uri.parse('https://example.com/referral?code=MYSHOP-AB12CD'),
        ),
        isNull,
      );
      expect(
        parseReferralCode(Uri.parse('myshop://referral?code=WRONG')),
        isNull,
      );
    });
  });
}
