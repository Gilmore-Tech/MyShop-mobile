import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/auth/screens/phone_input_screen.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _TestClientAuthController extends ClientAuthController {
  _TestClientAuthController(ClientAuthState initial)
      : super(
          ClientAuthRepository(
            service: MockAuthService(),
            tokenStorage: _MockTokenStorage(),
            deviceIdProvider: DeviceIdProvider(_MockTokenStorage()),
          ),
        ) {
    state = initial;
  }

  @override
  Future<void> bootstrap() async {}

  ClientAuthState get currentState => state;
}

void main() {
  testWidgets(
    'shows blocked-device dialog when the screen mounts already blocked',
    (tester) async {
      final controller = _TestClientAuthController(
        const AuthBlockedByOtherDevice(phone: '+233501234567'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clientAuthControllerProvider.overrideWith((_) => controller),
          ],
          child: const MaterialApp(home: PhoneInputScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Already signed in elsewhere'), findsOneWidget);
      expect(find.text('Sign me in here'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.currentState, isA<AuthUnauthenticated>());
      expect(find.text('Already signed in elsewhere'), findsNothing);
    },
  );
}
