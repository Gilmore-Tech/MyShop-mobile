import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

void main() {
  group('RegisterRequest.toJson — vehicle details (driver signup)', () {
    test('includes all vehicle fields when set', () {
      final json = const RegisterRequest(
        phone: '+233241234567',
        fullName: 'Kofi Mensah',
        type: 'driver',
        privacyPolicyAccepted: true,
        rideCategories: ['regular'],
        vehicleMake: 'Toyota',
        vehicleModel: 'Corolla',
        vehicleYear: 2018,
        vehiclePlate: 'GR-1234-20',
        vehicleColor: 'Silver',
      ).toJson();

      expect(json['vehicleMake'], 'Toyota');
      expect(json['vehicleModel'], 'Corolla');
      expect(json['vehicleYear'], 2018);
      expect(json['vehiclePlate'], 'GR-1234-20');
      expect(json['vehicleColor'], 'Silver');
    });

    test('omits vehicle keys entirely when null (non-driver signup)', () {
      final json = const RegisterRequest(
        phone: '+233241234567',
        fullName: 'Ama Owusu',
        type: 'client',
        privacyPolicyAccepted: true,
      ).toJson();

      expect(json.containsKey('vehicleMake'), isFalse);
      expect(json.containsKey('vehicleModel'), isFalse);
      expect(json.containsKey('vehicleYear'), isFalse);
      expect(json.containsKey('vehiclePlate'), isFalse);
      expect(json.containsKey('vehicleColor'), isFalse);
    });
  });
}
