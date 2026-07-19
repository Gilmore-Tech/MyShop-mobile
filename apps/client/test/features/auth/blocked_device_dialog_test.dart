import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/auth/screens/phone_input_screen.dart';

const _recoveryChallenge = 'opaque-recovery-challenge-1234567890';

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

  @override
  Future<void> requestSessionRecovery() async {
    final current = state;
    if (current is! AuthBlockedByOtherDevice) return;
    state = AuthBlockedByOtherDevice(
      phone: current.phone,
      recoveryChallenge: current.recoveryChallenge,
      recoveryRequestStatus: RecoveryRequestStatus.sent,
      isTakingOver: current.isTakingOver,
      takeoverError: current.takeoverError,
    );
  }

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
      expect(find.text('Contact support'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.currentState, isA<AuthUnauthenticated>());
      expect(find.text('Already signed in elsewhere'), findsNothing);
    },
  );

  testWidgets('does not promise that support was notified', (tester) async {
    final controller = _TestClientAuthController(
      const AuthBlockedByOtherDevice(
        phone: '+233501234567',
        recoveryChallenge: _recoveryChallenge,
      ),
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
}
