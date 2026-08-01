import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';

class _MockClientAuthRepository extends Mock implements ClientAuthRepository {}

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

void main() {
  test('client registration preserves the stable retained-role support signal',
      () async {
    final repository = _MockClientAuthRepository();
    final controller = ClientAuthController(repository);
    when(
      () => repository.register(
        phone: '+233241234567',
        fullName: 'Ama Mensah',
        legalAcceptances: _legalAcceptances,
        email: null,
        referralCode: null,
      ),
    ).thenThrow(
      const ConflictException(
        message: 'backend detail must not be shown',
        errorCode: AuthErrorCodes.roleAccountRetained,
      ),
    );

    await controller.register(
      phone: '+233241234567',
      fullName: 'Ama Mensah',
      legalAcceptances: _legalAcceptances,
    );

    final state = controller.state;
    expect(state, isA<AuthNeedsRegistration>());
    expect(
        (state as AuthNeedsRegistration).requiresRoleRecoverySupport, isTrue);
    expect(state.error, contains('cannot be registered again'));
    expect(state.error, isNot(contains('backend detail')));
  });
}
