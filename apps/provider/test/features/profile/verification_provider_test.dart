import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/verification_provider.dart';

void main() {
  AuthUser approvedArtisan() {
    return AuthUser(
      id: 'user_1',
      phone: '+233241234567',
      fullName: 'Artisan One',
      role: AuthRole.artisan,
      artisanProfile: ArtisanProfile(
        id: 'artisan_1',
        legalName: 'Artisan One',
        verificationStatus: 'approved',
        kycStatus: 'approved',
        policeCheckStatus: 'approved',
        onlineStatus: 'offline',
        serviceRadiusKm: 5,
        shopCapacity: 'solo',
        maxConcurrentJobs: 1,
        payoutPreference: 'standard',
        completedJobsCount: 0,
        cancellationCount30d: 0,
        ghanaCardVerified: true,
        languagePref: 'en',
        serviceCategories: const [
          ServiceCategoryLink(
            categoryId: 'category_1',
            category: ServiceCategory(
              id: 'category_1',
              name: 'Electrician',
              slug: 'electrician',
            ),
          ),
        ],
      ),
    );
  }

  AuthUser approvedDriver() {
    return AuthUser(
      id: 'user_driver',
      phone: '+233241234568',
      fullName: 'Driver One',
      role: AuthRole.driver,
      driverProfile: const DriverProfile(
        id: 'driver_1',
        legalName: 'Driver One',
        displayName: 'Driver One',
        verificationStatus: 'approved',
        kycStatus: 'approved',
        policeCheckStatus: 'approved',
        onlineStatus: 'offline',
        serviceRadiusKm: 5,
        payoutPreference: 'standard',
        cancellationCount30d: 0,
        ghanaCardVerified: true,
        languagePref: 'en',
      ),
    );
  }

  DocumentInfo approvedDocument(DocumentType type, {String? expiresAt}) {
    return DocumentInfo(
      id: '${type.value}_1',
      providerType: 'artisan',
      documentType: type.value,
      status: 'approved',
      isCurrent: true,
      createdAt: '2026-07-17T00:00:00Z',
      expiresAt: expiresAt,
    );
  }

  Future<ProfileCompletion> completionWith(
    List<DocumentInfo> credentialDocuments, {
    bool includeProfilePhoto = true,
    Map<String, dynamic>? artisanData = const {
      'verificationStatus': 'approved',
    },
  }) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(approvedArtisan()),
        providerTypeProvider.overrideWith((ref) => ProviderType.artisan),
        verificationStatusProvider.overrideWith(
          (ref) async => VerificationStatusResponse(
            artisanData: artisanData,
            documents: [
              if (includeProfilePhoto)
                approvedDocument(DocumentType.profilePhoto),
              approvedDocument(DocumentType.ghanaCard),
              ...credentialDocuments,
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(verificationStatusProvider.future);
    return container.read(profileCompletionProvider);
  }

  test('approved business registration alone completes artisan documents',
      () async {
    final completion = await completionWith([
      approvedDocument(DocumentType.businessRegistration),
    ]);

    expect(completion.isComplete, isTrue);
    expect(completion.missing, isEmpty);
  });

  test('approved trade certificate alone completes artisan documents',
      () async {
    final completion = await completionWith([
      approvedDocument(DocumentType.tradeCertificate),
    ]);

    expect(completion.isComplete, isTrue);
    expect(completion.missing, isEmpty);
  });

  test('artisan profile photo does not block go-live eligibility', () async {
    final completion = await completionWith(
      [approvedDocument(DocumentType.tradeCertificate)],
      includeProfilePhoto: false,
    );

    expect(completion.isComplete, isTrue);
    expect(completion.missing, isNot(contains('Profile photo (approved)')));
  });

  test(
      'driver role completion defers vehicle evidence to selected-vehicle preflight',
      () async {
    DocumentInfo driverDocument(DocumentType type, {String? expiresAt}) {
      return DocumentInfo(
        id: '${type.value}_driver',
        providerType: 'driver',
        documentType: type.value,
        status: 'approved',
        isCurrent: true,
        createdAt: '2026-07-17T00:00:00Z',
        expiresAt: expiresAt,
      );
    }

    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(approvedDriver()),
        providerTypeProvider.overrideWith((ref) => ProviderType.driver),
        verificationStatusProvider.overrideWith(
          (ref) async => VerificationStatusResponse(
            driverData: const {'verificationStatus': 'approved'},
            documents: [
              driverDocument(DocumentType.profilePhoto),
              driverDocument(DocumentType.ghanaCard),
              driverDocument(
                DocumentType.driversLicence,
                expiresAt: '2027-07-17',
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(verificationStatusProvider.future);

    final completion = container.read(profileCompletionProvider);
    expect(completion.isComplete, isTrue);
    expect(completion.missing, isNot(contains('Vehicle information')));
    expect(
      completion.missing,
      isNot(contains('Insurance Certificate (approved)')),
    );
  });

  test('artisan is missing one combined credential when neither is approved',
      () async {
    final completion = await completionWith(const []);

    expect(completion.isComplete, isFalse);
    expect(
      completion.missing,
      contains('Business Registration or Trade Certificate (approved)'),
    );
    expect(completion.missing,
        isNot(contains('Business Registration (approved)')));
    expect(completion.missing, isNot(contains('Trade Certificate (approved)')));
  });

  test('omitted role block falls back to approved profile snapshot', () async {
    final completion = await completionWith(
      [approvedDocument(DocumentType.tradeCertificate)],
      artisanData: null,
    );

    expect(completion.isComplete, isTrue);
    expect(completion.missing, isEmpty);
  });

  test('explicit pending role status overrides approved profile snapshot',
      () async {
    final completion = await completionWith(
      [approvedDocument(DocumentType.tradeCertificate)],
      artisanData: const {'verificationStatus': 'pending'},
    );

    expect(completion.isComplete, isFalse);
    expect(
        completion.missing, contains('Final provider verification is pending'));
    expect(completion.missing, isNot(contains('Ghana Card (approved)')));
    expect(
      completion.missing,
      isNot(contains('Business Registration or Trade Certificate (approved)')),
    );
  });

  test('verification endpoint failure is not presented as missing documents',
      () async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(approvedArtisan()),
        providerTypeProvider.overrideWith((ref) => ProviderType.artisan),
        verificationStatusProvider.overrideWith(
          (ref) => Future<VerificationStatusResponse>.error(
            StateError('network unavailable'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(verificationStatusProvider.future),
      throwsStateError,
    );
    final completion = container.read(profileCompletionProvider);

    expect(completion.verificationUnavailable, isTrue);
    expect(completion.missing, hasLength(1));
    expect(completion.missing.single, contains("couldn't verify"));
    expect(completion.missing.single, isNot(contains('Ghana Card')));
  });

  test(
      'artisan is not eligible when both mutually exclusive credentials are approved',
      () async {
    final completion = await completionWith([
      approvedDocument(DocumentType.businessRegistration),
      approvedDocument(DocumentType.tradeCertificate),
    ]);

    expect(completion.isComplete, isFalse);
    expect(
      completion.missing,
      contains('Keep exactly one approved trade credential (contact support)'),
    );
  });

  group('effectiveProviderVerificationStatus', () {
    test('fresh rejected response overrides a stale approved profile', () {
      expect(
        effectiveProviderVerificationStatus(
          verification: const VerificationStatusResponse(
            driverData: {'verificationStatus': 'rejected'},
            documents: [],
          ),
          providerType: 'driver',
          profileStatus: 'approved',
        ),
        'rejected',
      );
    });

    test('fresh suspended response is not presented as pending', () {
      expect(
        effectiveProviderVerificationStatus(
          verification: const VerificationStatusResponse(
            artisanData: {'verificationStatus': 'suspended'},
            documents: [],
          ),
          providerType: 'artisan',
          profileStatus: 'pending',
        ),
        'suspended',
      );
    });

    test('omitted role block retains the legacy profile fallback', () {
      expect(
        effectiveProviderVerificationStatus(
          verification: const VerificationStatusResponse(documents: []),
          providerType: 'artisan',
          profileStatus: 'approved',
        ),
        'approved',
      );
    });
  });
}
