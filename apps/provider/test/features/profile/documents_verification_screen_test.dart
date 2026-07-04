import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/verification_provider.dart';
import 'package:myshop_provider/src/features/profile/screens/documents_verification_screen.dart';

void main() {
  AuthUser driverUser({
    bool ghanaCardVerified = true,
    String? licenceNumber = 'DRV-12345',
    String? profilePhotoUrl,
  }) {
    return AuthUser(
      id: 'user_1',
      phone: '+233241234567',
      fullName: 'Fresh Driver',
      role: AuthRole.driver,
      driverProfile: DriverProfile(
        id: 'driver_1',
        legalName: 'Fresh Driver',
        displayName: 'Fresh Driver',
        ghanaCardVerified: ghanaCardVerified,
        verificationStatus: 'pending',
        kycStatus: 'not_started',
        policeCheckStatus: 'not_started',
        onlineStatus: 'offline',
        serviceRadiusKm: 5,
        payoutPreference: 'standard',
        cancellationCount30d: 0,
        languagePref: 'en',
        profilePhotoUrl: profilePhotoUrl,
        licenceNumber: licenceNumber,
        vehicleMake: 'Toyota',
      ),
    );
  }

  Widget screen({
    required AuthUser user,
    required VerificationStatusResponse verification,
  }) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        providerTypeProvider.overrideWith((ref) => ProviderType.driver),
        verificationStatusProvider.overrideWith((ref) async => verification),
      ],
      child: const MaterialApp(home: DocumentsVerificationScreen()),
    );
  }

  testWidgets(
    'does not mark profile fields as approved documents when no driver document rows exist',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(),
          verification: const VerificationStatusResponse(documents: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Driver's License"), findsOneWidget);
      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Upload a clear face photo'), findsOneWidget);
      expect(
          find.text('Licence number saved — upload document'), findsOneWidget);
      expect(find.text('Identity verified — upload document'), findsOneWidget);
      expect(find.text('Approved'), findsNothing);
      expect(find.text('Upload'), findsWidgets);
    },
  );

  testWidgets(
    'still prompts profile photo upload when only the profile URL exists',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(profilePhotoUrl: 'https://cdn.example/stale.jpg'),
          verification: const VerificationStatusResponse(documents: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Upload a clear face photo'), findsOneWidget);
      expect(find.text('Photo saved — awaiting document review'), findsNothing);
      expect(find.text('Upload'), findsWidgets);
    },
  );

  testWidgets(
    'ignores approved documents from a sibling provider role on the driver screen',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(ghanaCardVerified: false, licenceNumber: null),
          verification: VerificationStatusResponse(
            documents: [
              DocumentInfo(
                id: 'artisan_ghana_card_1',
                providerType: 'artisan',
                documentType: DocumentType.ghanaCard.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-02T00:00:00Z',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tap to upload front & back'), findsOneWidget);
      expect(find.text('Approved'), findsNothing);
      expect(find.text('Upload'), findsWidgets);
    },
  );

  testWidgets(
    'locks approved profile photo immediately after admin approval',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(profilePhotoUrl: 'https://cdn.example/driver.jpg'),
          verification: VerificationStatusResponse(
            documents: [
              DocumentInfo(
                id: 'driver_profile_photo_1',
                providerType: 'driver',
                documentType: DocumentType.profilePhoto.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-02T00:00:00Z',
                fileUrl: 'https://cdn.example/driver.jpg',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Approved — contact support to change'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);

      await tester.tap(find.text('Profile Photo'));
      await tester.pumpAndSettle();

      expect(find.text('Choose new document'), findsNothing);
    },
  );

  testWidgets(
    'shows final approved profile photo as support-locked after RM verification',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(profilePhotoUrl: 'https://cdn.example/driver.jpg'),
          verification: VerificationStatusResponse(
            driverData: const {'verificationStatus': 'approved'},
            documents: [
              DocumentInfo(
                id: 'driver_profile_photo_1',
                providerType: 'driver',
                documentType: DocumentType.profilePhoto.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-02T00:00:00Z',
                fileUrl: 'https://cdn.example/driver.jpg',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile Photo'), findsOneWidget);
      expect(find.text('Approved — contact support to change'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
    },
  );
}
