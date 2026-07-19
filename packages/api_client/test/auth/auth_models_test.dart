import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

UserProfile profileWithRole(String role, Map<String, dynamic> roleProfile) {
  return UserProfile.fromJson({
    'id': '$role-account-id',
    'phone': '+233241234567',
    'fullName': 'Shared Human Name',
    'languagePref': 'en',
    'status': 'active',
    'createdAt': '2026-07-18T00:00:00.000Z',
    'updatedAt': '2026-07-18T00:00:00.000Z',
    role: roleProfile,
  });
}

void main() {
  group('AuthUser role identity isolation', () {
    test('never falls back to a shared root name', () {
      final client = AuthUser.fromProfile(
        profileWithRole('client', {'id': 'client-account-id'}),
        activeRole: AuthRole.client,
      );
      final driver = AuthUser.fromProfile(
        profileWithRole('driver', {'id': 'driver-account-id'}),
        activeRole: AuthRole.driver,
      );
      final artisan = AuthUser.fromProfile(
        profileWithRole('artisan', {'id': 'artisan-account-id'}),
        activeRole: AuthRole.artisan,
      );

      expect(client.fullName, 'Client');
      expect(driver.fullName, 'Driver');
      expect(artisan.fullName, 'Artisan');
      expect(
        [client.fullName, driver.fullName, artisan.fullName],
        isNot(contains('Shared Human Name')),
      );
    });

    test('uses only the active role profile name', () {
      final client = AuthUser.fromProfile(
        profileWithRole('client', {
          'id': 'client-account-id',
          'displayName': 'Client Display',
        }),
        activeRole: AuthRole.client,
      );
      final driver = AuthUser.fromProfile(
        profileWithRole('driver', {
          'id': 'driver-account-id',
          'legalName': 'Driver Legal',
        }),
        activeRole: AuthRole.driver,
      );
      final artisan = AuthUser.fromProfile(
        profileWithRole('artisan', {
          'id': 'artisan-account-id',
          'businessName': 'Artisan Business',
        }),
        activeRole: AuthRole.artisan,
      );

      expect(client.fullName, 'Client Display');
      expect(driver.fullName, 'Driver Legal');
      expect(artisan.fullName, 'Artisan Business');
    });
  });
}
