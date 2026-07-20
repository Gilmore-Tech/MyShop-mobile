import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

Map<String, dynamic> clientJson({Object? loyaltyPointsBalance}) => {
      'id': 'client-account-id',
      'languagePref': 'en',
      'ghanaCardVerified': false,
      'kycStatus': 'not_started',
      if (loyaltyPointsBalance != null)
        'loyaltyPointsBalance': loyaltyPointsBalance,
    };

void main() {
  group('ClientProfile loyalty ownership', () {
    test('keeps an omitted balance unavailable instead of fabricating zero',
        () {
      final profile = ClientProfile.fromJson(clientJson());

      expect(profile.loyaltyPointsBalance, isNull);
    });

    test('preserves an explicit role-owned zero balance', () {
      final profile = ClientProfile.fromJson(
        clientJson(loyaltyPointsBalance: 0),
      );

      expect(profile.loyaltyPointsBalance, 0);
    });

    test('preserves an explicit role-owned positive balance', () {
      final profile = ClientProfile.fromJson(
        clientJson(loyaltyPointsBalance: 42),
      );

      expect(profile.loyaltyPointsBalance, 42);
    });
  });
}
