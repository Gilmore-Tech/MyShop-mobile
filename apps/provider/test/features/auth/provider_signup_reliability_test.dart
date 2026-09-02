import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/registration/providers/registration_controller.dart';
import 'package:shared_models/shared_models.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthService extends Mock implements AuthService {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockDeviceIdProvider extends Mock implements DeviceIdProvider {}

const _phone = '+233241234567';
const _legalAcceptances = <LegalAcceptanceSelection>[
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

DriverRegistrationDraft _completeDriverDraft(String fullName) =>
    DriverRegistrationDraft(
      fullName: fullName,
      email: 'driver@example.com',
      ghanaCardNumber: 'GHA-123456789-0',
      vehicleMake: 'Toyota',
      vehicleModel: 'Corolla',
      vehicleYear: '2020',
      vehiclePlate: 'GR 1234-20',
      vehicleColor: 'Black',
      rideCategories: const ['regular'],
    );

ArtisanRegistrationDraft _completeArtisanDraft(String fullName) =>
    ArtisanRegistrationDraft(
      fullName: fullName,
      email: 'artisan@example.com',
      ghanaCardNumber: 'GHA-123456789-0',
      businessName: 'Plumbing Services',
      tradeCategory: 'Plumber',
      serviceCategories: const ['11111111-1111-4111-8111-111111111111'],
    );

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RegisterRequest(
        phone: _phone,
        fullName: 'Fallback',
        type: 'driver',
        legalAcceptances: _legalAcceptances,
      ),
    );
  });

  test('final draft validation identifies the first section to correct', () {
    final incompleteDriver = DriverRegistrationDraft(
      fullName: 'Kofi Mensah',
      email: 'kofi@example.com',
      ghanaCardNumber: 'GHA-123456789-0',
      rideCategories: const ['regular'],
    );
    final validArtisan = ArtisanRegistrationDraft(
      fullName: 'Ama Mensah',
      email: 'ama@example.com',
      ghanaCardNumber: 'GHA-123456789-0',
      businessName: 'Ama Plumbing',
      tradeCategory: 'Plumber',
      serviceCategories: const ['11111111-1111-4111-8111-111111111111'],
    );

    expect(firstDriverRegistrationIssue(incompleteDriver)?.step, 1);
    expect(firstArtisanRegistrationIssue(validArtisan), isNull);
    expect(validateOptionalReferralCode(''), isNull);
  });

  test('personal-name validation guards both provider registration drafts', () {
    for (final invalidName in const [
      'Driver123',
      'Artisan😀',
      'Am\uFE0E',
      'Am\uFE0F',
    ]) {
      expect(
        firstDriverRegistrationIssue(_completeDriverDraft(invalidName))?.step,
        0,
        reason: invalidName,
      );
      expect(
        firstArtisanRegistrationIssue(_completeArtisanDraft(invalidName))?.step,
        0,
        reason: invalidName,
      );
    }

    for (final validName in const [
      'Ɛsi Ɔfori',
      'Élodie',
      'E\u0301lodie',
      'O’Connor',
      'NʼDour',
      'Osei-Tutu',
      '李小龙',
    ]) {
      expect(
        firstDriverRegistrationIssue(_completeDriverDraft(validName)),
        isNull,
        reason: validName,
      );
      expect(
        firstArtisanRegistrationIssue(_completeArtisanDraft(validName)),
        isNull,
        reason: validName,
      );
    }
  });

  test('backend failures identify the section to correct', () {
    expect(
      registrationCorrectionForErrorCode(
        'INVALID_REFERRAL_CODE',
        ProviderType.driver,
      )?.step,
      0,
    );
    expect(
      registrationCorrectionForErrorCode(
        'INVALID_VEHICLE_PLATE',
        ProviderType.driver,
      )?.step,
      1,
    );
    expect(
      registrationCorrectionForErrorCode(
        'INVALID_RIDE_CATEGORY',
        ProviderType.driver,
      )?.step,
      2,
    );
    expect(
      registrationCorrectionForErrorCode(
        'INVALID_CATEGORY',
        ProviderType.artisan,
      )?.step,
      1,
    );
    expect(
      registrationCorrectionForErrorCode(
        AuthErrorCodes.invalidPersonName,
        ProviderType.driver,
      )?.step,
      0,
    );
    expect(
      registrationCorrectionForErrorCode(
        'REGISTRATION_RESTART_REQUIRED',
        ProviderType.artisan,
      )?.step,
      0,
    );
  });

  test(
      'controller preserves correction code without using a support UUID as field copy',
      () async {
    final repository = _MockAuthRepository();
    final controller = AuthController(
      repository,
      tokenStorage: _MockTokenStorage(),
    );
    when(() => repository.register(any())).thenThrow(
      const ApiException(
        message: 'inactive database category',
        statusCode: 400,
        errorCode: 'INVALID_RIDE_CATEGORY',
        details: {
          'supportReference': '15286d11-fceb-43e6-ac0e-41f96d9a1b77',
        },
      ),
    );

    await controller.registerAndSendOtp(
      phone: _phone,
      fullName: 'Kwame Mensah',
      type: 'driver',
      legalAcceptances: _legalAcceptances,
      role: ProviderType.driver,
      rideCategories: const ['standard'],
    );

    final state = controller.state as AuthUnauthenticated;
    expect(state.errorCode, 'INVALID_RIDE_CATEGORY');
    expect(state.error, contains('no longer available'));
    expect(
        state.error, isNot(contains('15286d11-fceb-43e6-ac0e-41f96d9a1b77')));
    expect(state.error, isNot(contains('inactive database category')));
  });

  test('an omitted referral does not block provider registration', () async {
    final repository = _MockAuthRepository();
    final controller = AuthController(
      repository,
      tokenStorage: _MockTokenStorage(),
    );
    when(() => repository.register(any())).thenAnswer((_) async {});

    await controller.registerAndSendOtp(
      phone: _phone,
      fullName: 'Kwame Mensah',
      type: 'driver',
      legalAcceptances: _legalAcceptances,
      role: ProviderType.driver,
      rideCategories: const ['standard'],
    );

    final request = verify(() => repository.register(captureAny()))
        .captured
        .single as RegisterRequest;
    expect(request.referralCode, isNull);
    expect(controller.state, isA<AuthOtpSent>());
  });

  test('successful OTP request does not write pre-auth secure state', () async {
    final service = _MockAuthService();
    final storage = _MockTokenStorage();
    final device = _MockDeviceIdProvider();
    final repository = AuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: device,
    );
    when(() => device.ensureDeviceId()).thenAnswer((_) async => 'device-1');
    when(() => device.readDeviceInfo()).thenAnswer((_) async => 'test-device');
    when(() => service.register(any())).thenAnswer((_) async {});

    await repository.register(
      const RegisterRequest(
        phone: _phone,
        fullName: 'Kofi Mensah',
        type: 'driver',
        legalAcceptances: _legalAcceptances,
      ),
    );

    verifyNever(() => storage.writePhone(any()));
    verifyNever(() => storage.writeRole(any()));
    verifyNever(
      () => storage.writeTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    );
  });
}
