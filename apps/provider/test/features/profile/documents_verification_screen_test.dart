import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_vehicle_provider.dart';
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

  ProviderVehicle vehicle({
    required String id,
    required String make,
    required String model,
    required String plate,
  }) {
    return ProviderVehicle(
      id: id,
      make: make,
      model: model,
      year: 2024,
      plate: plate,
      color: 'Silver',
      isActive: true,
      approvalStatus: ProviderVehicleApprovalStatus.approved,
      version: 1,
      rejectionReason: null,
      coordinatorReviewedAt: null,
      regionalManagerReviewedAt: null,
      retirementRequestedAt: null,
      retirementRequestReason: null,
      rideCategories: const [],
      pendingRevision: null,
      eligible: true,
      reasonCodes: const [],
    );
  }

  Widget screen({
    required AuthUser user,
    required VerificationStatusResponse verification,
    List<ProviderVehicle> vehicles = const [],
    String? activeVehicleId,
  }) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        providerTypeProvider.overrideWith((ref) => ProviderType.driver),
        verificationStatusProvider.overrideWith((ref) async => verification),
        providerVehiclesProvider.overrideWith(
          (ref) async => ProviderVehiclesResponse(
            activeVehicleId: activeVehicleId,
            onlineStatus: 'offline',
            legacyBackfillRequired: false,
            legacyReasonCode: null,
            vehicles: vehicles,
          ),
        ),
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
      expect(find.text('Roadworthiness Certificate'), findsOneWidget);
      expect(find.text('Insurance Certificate'), findsOneWidget);
      expect(find.text('Vehicle Registration'), findsNothing);
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
    'keeps a still-valid expiring document locked until its GMT expiry',
    (tester) async {
      final expiry = DateTime.now().toUtc().add(const Duration(days: 3));
      final expiryDate = [
        expiry.year.toString().padLeft(4, '0'),
        expiry.month.toString().padLeft(2, '0'),
        expiry.day.toString().padLeft(2, '0'),
      ].join('-');
      await tester.pumpWidget(
        screen(
          user: driverUser(),
          verification: VerificationStatusResponse(
            documents: [
              DocumentInfo(
                id: 'driver_licence_valid',
                providerType: 'driver',
                documentType: DocumentType.driversLicence.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-02T00:00:00Z',
                expiresAt: expiryDate,
                expired: false,
                providerReplacementAllowed: false,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expiring'), findsOneWidget);
      expect(find.textContaining('upload opens after expiry'), findsOneWidget);
      await tester.tap(find.text("Driver's License"));
      await tester.pumpAndSettle();
      expect(find.text("Re-upload Driver's License"), findsNothing);
    },
  );

  testWidgets(
    'reopens replacement only after the server marks the document expired',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(),
          verification: VerificationStatusResponse(
            documents: [
              DocumentInfo(
                id: 'driver_licence_expired',
                providerType: 'driver',
                documentType: DocumentType.driversLicence.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-02T00:00:00Z',
                expiresAt: '2020-01-01',
                expired: true,
                providerReplacementAllowed: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expired'), findsOneWidget);
      await tester.tap(find.text("Driver's License"));
      await tester.pumpAndSettle();
      expect(find.text("Re-upload Driver's License"), findsOneWidget);
    },
  );

  testWidgets(
    'shows an independently approved document while provider approval is pending',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(ghanaCardVerified: true),
          verification: VerificationStatusResponse(
            driverData: const {'verificationStatus': 'pending'},
            documents: [
              DocumentInfo(
                id: 'driver_ghana_card_1',
                providerType: 'driver',
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

      expect(find.text('Ghana Card'), findsOneWidget);
      expect(find.text('Approved'), findsNWidgets(2));
      expect(
          find.text('In review — awaiting final verification'), findsNothing);
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

  testWidgets(
    'keeps roadworthiness and insurance records separate for each vehicle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final firstVehicle = vehicle(
        id: 'vehicle_1',
        make: 'Toyota',
        model: 'Corolla',
        plate: 'GR-1111-24',
      );
      final secondVehicle = vehicle(
        id: 'vehicle_2',
        make: 'Honda',
        model: 'Civic',
        plate: 'GW-2222-24',
      );
      await tester.pumpWidget(
        screen(
          user: driverUser(),
          vehicles: [firstVehicle, secondVehicle],
          activeVehicleId: firstVehicle.id,
          verification: VerificationStatusResponse(
            documents: [
              DocumentInfo(
                id: 'road_1',
                providerType: 'driver',
                documentType: DocumentType.roadworthinessCertificate.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
                expiresAt: '2030-01-01',
                vehicleId: firstVehicle.id,
              ),
              DocumentInfo(
                id: 'insurance_1',
                providerType: 'driver',
                documentType: DocumentType.vehicleInsurance.value,
                status: 'rejected',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
                rejectionReason: 'First vehicle insurance rejected',
                vehicleId: firstVehicle.id,
              ),
              DocumentInfo(
                id: 'road_2',
                providerType: 'driver',
                documentType: DocumentType.roadworthinessCertificate.value,
                status: 'rejected',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
                rejectionReason: 'Second vehicle roadworthiness rejected',
                vehicleId: secondVehicle.id,
              ),
              DocumentInfo(
                id: 'insurance_2',
                providerType: 'driver',
                documentType: DocumentType.vehicleInsurance.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
                expiresAt: '2031-02-02',
                vehicleId: secondVehicle.id,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Valid until 1 Jan 2030'), findsOneWidget);
      expect(find.text('First vehicle insurance rejected'), findsOneWidget);
      expect(
        find.text('Second vehicle roadworthiness rejected'),
        findsNothing,
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Honda Civic · GW-2222-24').last);
      await tester.pumpAndSettle();

      expect(find.text('Valid until 1 Jan 2030'), findsNothing);
      expect(find.text('First vehicle insurance rejected'), findsNothing);
      expect(
        find.text('Second vehicle roadworthiness rejected'),
        findsOneWidget,
      );
      expect(find.text('Valid until 2 Feb 2031'), findsOneWidget);
    },
  );
}
