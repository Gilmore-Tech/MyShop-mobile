import 'package:api_client/api_client.dart';
import 'package:test/test.dart';
import 'package:shared_models/shared_models.dart';

const legalAcceptances = <LegalAcceptanceSelection>[
  LegalAcceptanceSelection(
    slug: 'terms',
    documentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    version: '1.4.1',
  ),
  LegalAcceptanceSelection(
    slug: 'privacy',
    documentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    version: '1.4.1',
  ),
];

void main() {
  test('auth requests serialize deviceInfo using the backend string contract',
      () {
    const deviceInfo = 'Google Pixel 8 — Android 16';

    final login = const LoginRequest(
      phone: '+233241234567',
      deviceId: 'device-id',
      deviceInfo: deviceInfo,
    ).toJson();
    final registration = const RegisterRequest(
      phone: '+233241234567',
      fullName: 'Ama Owusu',
      type: 'client',
      legalAcceptances: legalAcceptances,
      deviceId: 'device-id',
      deviceInfo: deviceInfo,
    ).toJson();

    expect(login['deviceInfo'], deviceInfo);
    expect(registration['deviceInfo'], deviceInfo);
  });

  group('RegisterRequest.toJson — vehicle details (driver signup)', () {
    test('includes all vehicle fields when set', () {
      final json = const RegisterRequest(
        phone: '+233241234567',
        fullName: 'Kofi Mensah',
        type: 'driver',
        legalAcceptances: legalAcceptances,
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
        legalAcceptances: legalAcceptances,
      ).toJson();

      expect(json.containsKey('vehicleMake'), isFalse);
      expect(json.containsKey('vehicleModel'), isFalse);
      expect(json.containsKey('vehicleYear'), isFalse);
      expect(json.containsKey('vehiclePlate'), isFalse);
      expect(json.containsKey('vehicleColor'), isFalse);
    });
  });

  test('session recovery always serializes its exact target role', () {
    final json = const SessionRecoveryRequest(
      challenge: 'opaque-recovery-challenge-1234567890',
      phone: '+233241234567',
      deviceId: 'new-device',
      role: 'driver',
    ).toJson();

    expect(json, {
      'challenge': 'opaque-recovery-challenge-1234567890',
      'phone': '+233241234567',
      'deviceId': 'new-device',
      'role': 'driver',
    });
  });

  test(
      'deleted-role recovery binds request and verify payloads to one role and device',
      () {
    const base = RequestRoleAccountRecoveryOtpRequest(
      phone: '+233241234567',
      role: 'artisan',
      deviceId: 'install-device-id',
    );
    const verify = VerifyRoleAccountRecoveryOtpRequest(
      phone: '+233241234567',
      role: 'artisan',
      deviceId: 'install-device-id',
      otp: '123456',
      requestKey: '11111111-1111-4111-8111-111111111111',
    );

    expect(base.toJson(), {
      'phone': '+233241234567',
      'role': 'artisan',
      'deviceId': 'install-device-id',
    });
    expect(verify.toJson(), {
      'phone': '+233241234567',
      'role': 'artisan',
      'deviceId': 'install-device-id',
      'otp': '123456',
      'requestKey': '11111111-1111-4111-8111-111111111111',
    });
  });

  test('deleted-role recovery response keeps the exact role and deadline', () {
    final result = RoleAccountRecoveryResult.fromJson({
      'requestId': '11111111-1111-4111-8111-111111111111',
      'role': 'client',
      'status': 'pending_operations',
      'recoveryDeadline': '2026-10-17T12:00:00.000Z',
      'requestedAt': '2026-07-19T12:00:00.000Z',
    });

    expect(result.role, 'client');
    expect(result.status, 'pending_operations');
    expect(result.recoveryDeadline.toUtc(), DateTime.utc(2026, 10, 17, 12));
  });
}
