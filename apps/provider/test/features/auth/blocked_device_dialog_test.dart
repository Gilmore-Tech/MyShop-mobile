import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';
import 'package:myshop_provider/src/features/auth/data/auth_repository.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/auth/screens/phone_input_screen.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/registration/providers/registration_controller.dart';

const _recoveryChallenge = 'opaque-recovery-challenge-1234567890';

const _requiredDriverLegalDocuments = RequiredLegalDocuments(
  role: 'driver',
  documents: [
    LegalDocument(
      documentId: '11111111-1111-4111-8111-111111111111',
      slug: LegalSlugs.terms,
      title: 'Terms of Service',
      version: '1.4.1',
      audience: 'driver',
    ),
    LegalDocument(
      documentId: '22222222-2222-4222-8222-222222222222',
      slug: LegalSlugs.privacy,
      title: 'Privacy Notice',
      version: '1.4.1',
      audience: 'driver',
    ),
  ],
);

class _MockTokenStorage extends Mock implements TokenStorage {}

class _TestAuthController extends AuthController {
  _TestAuthController(
    AuthState initial, {
    this.retainOnRegistration = false,
    this.referralErrorOnFirstRegistrationCode,
  }) : super(
          AuthRepository(
            service: MockAuthService(),
            tokenStorage: _MockTokenStorage(),
            deviceIdProvider: DeviceIdProvider(_MockTokenStorage()),
          ),
          tokenStorage: _MockTokenStorage(),
        ) {
    state = initial;
  }

  final bool retainOnRegistration;
  final String? referralErrorOnFirstRegistrationCode;
  final List<String?> submittedReferralCodes = [];
  final List<String?> submittedEmails = [];
  bool _returnedReferralError = false;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> registerAndSendOtp({
    required String phone,
    required String fullName,
    required String type,
    required List<LegalAcceptanceSelection> legalAcceptances,
    ProviderType? role,
    String? displayName,
    String? businessName,
    String? email,
    List<String>? categories,
    List<String>? rideCategories,
    String? regionId,
    String? shopCapacity,
    String? referralCode,
    String? vehicleMake,
    String? vehicleModel,
    int? vehicleYear,
    String? vehiclePlate,
    String? vehicleColor,
  }) async {
    submittedReferralCodes.add(referralCode);
    submittedEmails.add(email);
    if (retainOnRegistration) {
      state = const AuthUnauthenticated(
        error:
            'This role was previously deleted and cannot be registered again. '
            'Contact support if you want to request recovery.',
        requiresRoleRecoverySupport: true,
      );
      return;
    }
    if (referralErrorOnFirstRegistrationCode != null &&
        referralCode != null &&
        !_returnedReferralError) {
      _returnedReferralError = true;
      state = AuthUnauthenticated(
        error: AuthErrorMapper.message(
          ApiException(
            message: 'backend details must stay hidden',
            statusCode: 503,
            errorCode: referralErrorOnFirstRegistrationCode,
          ),
        ),
        errorCode: referralErrorOnFirstRegistrationCode,
      );
      return;
    }
    state = AuthOtpSent(phone: phone, isNewUser: true, role: role);
  }

  @override
  Future<void> requestSessionRecovery() async {
    final current = state;
    if (current is! AuthBlockedByOtherDevice) return;
    state = AuthBlockedByOtherDevice(
      phone: current.phone,
      recoveryChallenge: current.recoveryChallenge,
      role: current.role,
      otpCode: current.otpCode,
      selectionToken: current.selectionToken,
      recoveryRequestStatus: RecoveryRequestStatus.sent,
      isTakingOver: current.isTakingOver,
      takeoverError: current.takeoverError,
    );
  }

  AuthState get currentState => state;
}

void main() {
  testWidgets(
    'shows blocked-device dialog when the screen mounts already blocked',
    (tester) async {
      final controller = _TestAuthController(
        const AuthBlockedByOtherDevice(phone: '+233501234567'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((_) => controller),
          ],
          child: const MaterialApp(
            home: ProviderPhoneInputScreen(mode: PhoneInputMode.signIn),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Already signed in elsewhere'), findsOneWidget);
      expect(find.text('Sign me in here'), findsOneWidget);
      expect(find.text('Contact support'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.currentState, isA<AuthUnauthenticated>());
      expect(find.text('Already signed in elsewhere'), findsNothing);
    },
  );

  testWidgets('does not promise that support was notified', (tester) async {
    final controller = _TestAuthController(
      const AuthBlockedByOtherDevice(
        phone: '+233501234567',
        recoveryChallenge: _recoveryChallenge,
        role: ProviderType.driver,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(
          home: ProviderPhoneInputScreen(mode: PhoneInputMode.signIn),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Contact support'));
    await tester.pump();

    expect(
      find.text(
        'Your request was received. If this role still has the matching active '
        'session, support can review it.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Support has been notified'), findsNothing);
  });

  testWidgets('retained provider role shows a recovery support action',
      (tester) async {
    final controller = _TestAuthController(
      const AuthUnauthenticated(),
      retainOnRegistration: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((_) => controller),
          registrationLegalDocumentsProvider.overrideWith(
            (_, __) async => _requiredDriverLegalDocuments,
          ),
          termsAcceptedProvider(ProviderType.driver).overrideWith((_) => true),
          privacyAcceptedProvider(ProviderType.driver)
              .overrideWith((_) => true),
          driverRegistrationProvider.overrideWith((_) {
            final draft = DriverRegistrationController();
            draft.update(
              DriverRegistrationDraft(
                fullName: 'Kofi Mensah',
                email: 'kofi@example.com',
                vehicleMake: 'Toyota',
                vehicleModel: 'Corolla',
                vehicleYear: '2020',
                vehiclePlate: 'GR 1234-20',
                vehicleColor: 'White',
                rideCategories: const ['regular'],
              ),
            );
            return draft;
          }),
        ],
        child: const MaterialApp(
          home: ProviderPhoneInputScreen(
            mode: PhoneInputMode.signUp,
            signUpRole: ProviderType.driver,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '501234567');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot be registered again'), findsOneWidget);
    expect(find.text('Request account recovery'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);

    await tester.ensureVisible(find.text('Request account recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request account recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Recover deleted driver role'), findsOneWidget);
    expect(find.byKey(const Key('role-recovery-send-code')), findsOneWidget);
  });

  testWidgets(
    'provider referral failure preserves the draft until explicit removal',
    (tester) async {
      final controller = _TestAuthController(
        const AuthUnauthenticated(),
        referralErrorOnFirstRegistrationCode:
            'PLATFORM_SIGNUP_ATTRIBUTION_SUSPENDED',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((_) => controller),
            registrationLegalDocumentsProvider.overrideWith(
              (_, __) async => _requiredDriverLegalDocuments,
            ),
            termsAcceptedProvider(ProviderType.driver)
                .overrideWith((_) => true),
            privacyAcceptedProvider(ProviderType.driver)
                .overrideWith((_) => true),
            driverRegistrationProvider.overrideWith((_) {
              final draft = DriverRegistrationController();
              draft.update(
                DriverRegistrationDraft(
                  fullName: 'Kofi Mensah',
                  email: '  kofi@example.com  ',
                  vehicleMake: 'Toyota',
                  vehicleModel: 'Corolla',
                  vehicleYear: '2020',
                  vehiclePlate: 'GR 1234-20',
                  vehicleColor: 'White',
                  rideCategories: const ['regular'],
                  referralCode: 'MYSHOP-ABC123',
                ),
              );
              return draft;
            }),
          ],
          child: const MaterialApp(
            home: ProviderPhoneInputScreen(
              mode: PhoneInputMode.signUp,
              signUpRole: ProviderType.driver,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '501234567');
      await tester.pump();
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(controller.submittedReferralCodes, ['MYSHOP-ABC123']);
      expect(controller.submittedEmails, ['kofi@example.com']);
      expect(
        find.textContaining(
          'Promotional signup codes are temporarily unavailable',
        ),
        findsOneWidget,
      );
      expect(find.text('Remove code and continue'), findsOneWidget);

      await tester.tap(find.text('Remove code and continue'));
      await tester.pumpAndSettle();

      expect(controller.submittedReferralCodes, ['MYSHOP-ABC123', null]);
      expect(find.text('Remove code and continue'), findsNothing);
    },
  );
}
