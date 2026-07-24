import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/providers/referral_provider.dart';
import 'package:myshop_provider/src/features/registration/providers/registration_controller.dart';

void main() {
  test('optional provider referral code uses the approved exact format', () {
    expect(validateOptionalReferralCode(''), isNull);
    expect(validateOptionalReferralCode('myshop-ab12cd'), isNull);
    expect(validateOptionalReferralCode('MYSHOP-TOO-LONG'), isNotNull);
    expect(validateOptionalReferralCode('ABC123'), isNotNull);
  });

  test('provider referral summary preserves server amounts in pesewas', () {
    final data = ProviderReferralData.fromJson({
      'code': 'MYSHOP-AB12CD',
      'shareLink': 'myshop://referral?code=MYSHOP-AB12CD',
      'rewardPesewas': 500,
      'totalReferrals': 3,
      'pendingPesewas': 500,
      'earnedPesewas': 1000,
    });

    expect(data.code, 'MYSHOP-AB12CD');
    expect(data.rewardGhs, 5);
    expect(data.pendingGhs, 5);
    expect(data.earnedGhs, 10);
  });
}
