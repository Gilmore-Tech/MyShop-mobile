import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_vehicle_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/verification_provider.dart';
import 'package:myshop_provider/src/features/profile/screens/documents_verification_screen.dart';

class _SeededDocumentUploadNotifier extends DocumentUploadNotifier {
  _SeededDocumentUploadNotifier(DocumentUploadState initialState)
      : super(VerificationService(Dio())) {
    state = initialState;
  }
}

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

  AuthUser artisanUser() {
    return AuthUser(
      id: 'artisan_user_1',
      phone: '+233241234569',
      fullName: 'Artisan One',
      role: AuthRole.artisan,
      artisanProfile: const ArtisanProfile(
        id: 'artisan_1',
        legalName: 'Artisan One',
        verificationStatus: 'pending',
        kycStatus: 'not_started',
        policeCheckStatus: 'not_started',
        onlineStatus: 'offline',
        serviceRadiusKm: 5,
        shopCapacity: 'solo',
        maxConcurrentJobs: 1,
        payoutPreference: 'standard',
        completedJobsCount: 0,
        cancellationCount30d: 0,
        ghanaCardVerified: false,
        languagePref: 'en',
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
    ProviderType providerType = ProviderType.driver,
    double textScale = 1,
    DocumentUploadState? uploadState,
  }) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        providerTypeProvider.overrideWith((ref) => providerType),
        verificationStatusProvider.overrideWith((ref) async => verification),
        if (uploadState != null)
          documentUploadProvider.overrideWith(
            (ref) => _SeededDocumentUploadNotifier(uploadState),
          ),
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
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const DocumentsVerificationScreen(),
      ),
    );
  }

  testWidgets(
    'artisan document sections do not overflow on a narrow phone with large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        screen(
          user: artisanUser(),
          providerType: ProviderType.artisan,
          textScale: 1.5,
          verification: const VerificationStatusResponse(documents: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PROVIDE EXACTLY ONE'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('OPTIONAL PROFILE & DOCUMENTS'),
        300,
      );
      expect(find.text('OPTIONAL PROFILE & DOCUMENTS'), findsOneWidget);
      expect(find.text('Does not block online'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'uses document progress instead of claiming a complete profile with a missing vehicle document',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selectedVehicle = vehicle(
        id: 'vehicle_1',
        make: 'Toyota',
        model: 'Corolla',
        plate: 'GR-1111-24',
      );

      await tester.pumpWidget(
        screen(
          user: driverUser(
            profilePhotoUrl: 'https://cdn.example/driver.jpg',
          ),
          vehicles: [selectedVehicle],
          activeVehicleId: selectedVehicle.id,
          verification: VerificationStatusResponse(
            driverData: const {'verificationStatus': 'approved'},
            documents: [
              DocumentInfo(
                id: 'profile_1',
                providerType: 'driver',
                documentType: DocumentType.profilePhoto.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
              ),
              DocumentInfo(
                id: 'licence_1',
                providerType: 'driver',
                documentType: DocumentType.driversLicence.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
                expiresAt: '2030-01-01',
              ),
              DocumentInfo(
                id: 'road_1',
                providerType: 'driver',
                documentType: DocumentType.roadworthinessCertificate.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
                expiresAt: '2030-01-01',
                vehicleId: selectedVehicle.id,
              ),
              DocumentInfo(
                id: 'ghana_1',
                providerType: 'driver',
                documentType: DocumentType.ghanaCard.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Complete your documents'), findsOneWidget);
      expect(
        find.text('80% uploaded · 4 of 5 documents · 4 approved'),
        findsOneWidget,
      );
      expect(find.text('Profile verification complete'), findsNothing);
      expect(find.text('Insurance Certificate'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
    },
  );

  testWidgets(
    'does not present an approved legacy vehicle document without expiry as eligible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selectedVehicle = vehicle(
        id: 'vehicle_1',
        make: 'Toyota',
        model: 'Corolla',
        plate: 'GR-1111-24',
      );

      await tester.pumpWidget(
        screen(
          user: driverUser(),
          vehicles: [selectedVehicle],
          activeVehicleId: selectedVehicle.id,
          verification: VerificationStatusResponse(
            documents: [
              DocumentInfo(
                id: 'road_without_expiry',
                providerType: 'driver',
                documentType: DocumentType.roadworthinessCertificate.value,
                status: 'approved',
                isCurrent: true,
                createdAt: '2026-07-01T00:00:00Z',
                vehicleId: selectedVehicle.id,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Expiry date required — contact support'),
        findsOneWidget,
      );
      expect(find.text('Action needed'), findsOneWidget);
      expect(
        find.text('20% uploaded · 1 of 5 documents · 0 approved'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'legacy RM rejection recovers a stranded driver document and keeps its reason',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(),
          verification: VerificationStatusResponse(
            driverData: const {
              'verificationStatus': 'rejected',
              'rejectionReason': 'The licence image is too blurry.',
            },
            documents: [
              DocumentInfo(
                id: 'old_upload_orphan',
                providerType: 'driver',
                documentType: DocumentType.driversLicence.value,
                status: 'uploaded',
                isCurrent: false,
                createdAt: '2026-08-15T00:00:00Z',
              ),
              DocumentInfo(
                id: 'current_licence',
                providerType: 'driver',
                documentType: DocumentType.driversLicence.value,
                status: 'coordinator_validated',
                isCurrent: true,
                createdAt: '2026-08-16T00:00:00Z',
                providerReplacementAllowed: false,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verification needs attention'), findsOneWidget);
      expect(
        find.textContaining('Reason: The licence image is too blurry.'),
        findsOneWidget,
      );
      expect(find.text('The licence image is too blurry.'), findsOneWidget);
      expect(find.text('Action required'), findsOneWidget);
      expect(
        find.text('Coordinator validated — awaiting Regional Manager'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'backend designates the exact vehicle document that must be replaced',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selectedVehicle = vehicle(
        id: 'vehicle_1',
        make: 'Toyota',
        model: 'Corolla',
        plate: 'GR-1111-24',
      );
      await tester.pumpWidget(
        screen(
          user: driverUser(),
          vehicles: [selectedVehicle],
          activeVehicleId: selectedVehicle.id,
          verification: VerificationStatusResponse(
            driverData: const {
              'verificationStatus': 'rejected',
              'resubmissionRequired': true,
              'resubmissionDocumentIds': ['insurance_vehicle_1'],
            },
            documents: [
              DocumentInfo(
                id: 'road_vehicle_1',
                providerType: 'driver',
                documentType: DocumentType.roadworthinessCertificate.value,
                status: 'coordinator_validated',
                isCurrent: true,
                createdAt: '2026-08-16T00:00:00Z',
                vehicleId: selectedVehicle.id,
                providerReplacementAllowed: false,
                resubmissionRequired: false,
              ),
              DocumentInfo(
                id: 'insurance_vehicle_1',
                providerType: 'driver',
                documentType: DocumentType.vehicleInsurance.value,
                status: 'coordinator_validated',
                isCurrent: true,
                createdAt: '2026-08-16T00:00:00Z',
                vehicleId: selectedVehicle.id,
                providerReplacementAllowed: true,
                resubmissionRequired: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No replacement requested for this document'),
          findsOneWidget);
      expect(find.text('No action'), findsOneWidget);
      expect(find.text('Replacement requested — tap to re-upload'),
          findsOneWidget);
      expect(find.text('Action required'), findsOneWidget);
    },
  );

  testWidgets(
    'artisan can re-upload a stranded trade credential after RM rejection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        screen(
          user: artisanUser(),
          providerType: ProviderType.artisan,
          verification: VerificationStatusResponse(
            artisanData: const {'verificationStatus': 'rejected'},
            documents: [
              DocumentInfo(
                id: 'trade_1',
                providerType: 'artisan',
                documentType: DocumentType.tradeCertificate.value,
                status: 'coordinator_validated',
                isCurrent: true,
                createdAt: '2026-08-16T00:00:00Z',
                providerReplacementAllowed: false,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verification needs attention'), findsOneWidget);
      expect(find.text('Replacement requested — tap to re-upload'),
          findsOneWidget);
      expect(find.text('Action required'), findsOneWidget);
    },
  );

  testWidgets(
    'authoritative same-session rejection clears optimistic uploaded copy',
    (tester) async {
      await tester.pumpWidget(
        screen(
          user: driverUser(),
          uploadState: const DocumentUploadState(
            uploaded: {'ghana_card': true},
          ),
          verification: VerificationStatusResponse(
            driverData: const {'verificationStatus': 'rejected'},
            documents: [
              DocumentInfo(
                id: 'ghana_1',
                providerType: 'driver',
                documentType: DocumentType.ghanaCard.value,
                status: 'rejected',
                isCurrent: true,
                createdAt: '2026-08-16T00:00:00Z',
                rejectionReason: 'Upload a clearer Ghana Card.',
                providerReplacementAllowed: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Upload a clearer Ghana Card.'), findsOneWidget);
      expect(find.text('Action required'), findsOneWidget);
      expect(find.text('Uploaded — pending review'), findsNothing);
    },
  );
}
