import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/verification_provider.dart';

void main() {
  AuthUser driverUser({String? profilePhotoUrl}) {
    return AuthUser(
      id: 'user_1',
      phone: '+233241234567',
      fullName: 'Driver One',
      role: AuthRole.driver,
      driverProfile: DriverProfile(
        id: 'driver_1',
        legalName: 'Driver One',
        displayName: 'Driver One',
        ghanaCardVerified: false,
        verificationStatus: 'pending',
        kycStatus: 'not_started',
        policeCheckStatus: 'not_started',
        onlineStatus: 'offline',
        serviceRadiusKm: 5,
        payoutPreference: 'standard',
        cancellationCount30d: 0,
        languagePref: 'en',
        profilePhotoUrl: profilePhotoUrl,
      ),
    );
  }

  ProviderContainer container({
    required AuthUser user,
    required VerificationStatusResponse verification,
  }) {
    final c = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        providerTypeProvider.overrideWith((ref) => ProviderType.driver),
        verificationStatusProvider.overrideWith((ref) async => verification),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
      'uses the approved active-role profile_photo document when user profile is stale',
      () async {
    const approvedUrl = 'https://cdn.example/approved-driver.jpg';
    final c = container(
      user: driverUser(),
      verification: VerificationStatusResponse(
        documents: [
          DocumentInfo(
            id: 'driver_profile_photo_1',
            providerType: 'driver',
            documentType: DocumentType.profilePhoto.value,
            status: 'approved',
            isCurrent: true,
            createdAt: '2026-07-02T00:00:00Z',
            fileUrl: approvedUrl,
          ),
        ],
      ),
    );

    await c.read(verificationStatusProvider.future);

    expect(c.read(providerProfilePhotoDisplayProvider).url, approvedUrl);
  });

  test('hides pending profile_photo even when the profile row has a URL',
      () async {
    final c = container(
      user: driverUser(profilePhotoUrl: 'https://cdn.example/pending.jpg'),
      verification: VerificationStatusResponse(
        documents: [
          DocumentInfo(
            id: 'driver_profile_photo_1',
            providerType: 'driver',
            documentType: DocumentType.profilePhoto.value,
            status: 'pending_review',
            isCurrent: true,
            createdAt: '2026-07-02T00:00:00Z',
            fileUrl: 'https://cdn.example/pending.jpg',
          ),
        ],
      ),
    );

    await c.read(verificationStatusProvider.future);

    expect(c.read(providerProfilePhotoDisplayProvider).url, isNull);
  });
}
