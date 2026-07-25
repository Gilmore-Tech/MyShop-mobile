import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/core/deep_links/referral_deep_link.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/auth/screens/sign_up_screen.dart';
import 'package:myshop_client/src/features/support/providers/support_providers.dart';

const _requiredClientLegalDocuments = RequiredLegalDocuments(
  role: 'client',
  documents: [
    LegalDocument(
      documentId: '11111111-1111-4111-8111-111111111111',
      slug: LegalSlugs.terms,
      title: 'Terms of Service',
      version: '1.4.1',
      audience: 'client',
    ),
    LegalDocument(
      documentId: '22222222-2222-4222-8222-222222222222',
      slug: LegalSlugs.privacy,
      title: 'Privacy Notice',
      version: '1.4.1',
      audience: 'client',
    ),
  ],
);

class _MockTokenStorage extends Mock implements TokenStorage {}

class _RedirectAuthController extends ClientAuthController {
  _RedirectAuthController(
    String phone, {
    bool requiresRoleRecoverySupport = false,
  }) : super(
          ClientAuthRepository(
            service: MockAuthService(),
            tokenStorage: _MockTokenStorage(),
            deviceIdProvider: DeviceIdProvider(_MockTokenStorage()),
          ),
        ) {
    state = AuthNeedsRegistration(
      phone: phone,
      error: requiresRoleRecoverySupport
          ? 'This role was previously deleted and cannot be registered again. '
              'Contact support to request recovery.'
          : null,
      requiresRoleRecoverySupport: requiresRoleRecoverySupport,
    );
  }

  String? registeredPhone;
  String? registeredReferralCode;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> register({
    required String phone,
    required String fullName,
    required List<LegalAcceptanceSelection> legalAcceptances,
    String? email,
    String? referralCode,
  }) async {
    registeredPhone = phone;
    registeredReferralCode = referralCode;
  }
}

void main() {
  testWidgets(
    'redirected valid phone keeps Create Account enabled and submits',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = _RedirectAuthController('+233241234567');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientAuthControllerProvider.overrideWith((_) => controller),
            pendingReferralCodeProvider.overrideWith((_) => 'MYSHOP-ABC123'),
            clientRegistrationLegalDocumentsProvider.overrideWith(
              (_) async => _requiredClientLegalDocuments,
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
              ),
              child: child!,
            ),
            home: const SignUpScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('was not applied'), findsNothing);
      expect(find.text('MYSHOP-ABC123'), findsWidgets);

      await tester.enterText(find.byType(TextField).first, 'Ama Mensah');
      await tester.pump();

      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((checkbox) => checkbox.value == false),
        isTrue,
      );

      var button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pump();
      button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(controller.registeredPhone, '+233241234567');
      expect(controller.registeredReferralCode, 'MYSHOP-ABC123');
    },
  );

  testWidgets('retained client role shows a recovery support action',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _RedirectAuthController(
      '+233241234567',
      requiresRoleRecoverySupport: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientAuthControllerProvider.overrideWith((_) => controller),
          pendingReferralCodeProvider.overrideWith((_) => null),
          clientRegistrationLegalDocumentsProvider.overrideWith(
            (_) async => _requiredClientLegalDocuments,
          ),
        ],
        child: const MaterialApp(home: SignUpScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot be registered again'), findsOneWidget);
    expect(find.text('Request account recovery'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);

    await tester.ensureVisible(find.text('Request account recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request account recovery'));
    await tester.pumpAndSettle();

    expect(find.text('Recover deleted client role'), findsOneWidget);
    expect(find.byKey(const Key('role-recovery-send-code')), findsOneWidget);
  });
}
