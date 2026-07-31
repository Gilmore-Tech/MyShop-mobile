import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/app/client_app.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/auth/screens/phone_input_screen.dart';
import 'package:myshop_client/src/features/onboarding/screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _HangingAuthService extends MockAuthService {
  @override
  Future<({UserProfile profile, Map<String, dynamic> raw})> getMeWithRaw() =>
      Completer<({UserProfile profile, Map<String, dynamic> raw})>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('waits for preferences, then leaves splash with no session',
      (tester) async {
    final storage = _MockTokenStorage();
    when(storage.readTokenSnapshot).thenAnswer(
      (_) async => const AuthTokenSnapshot.empty(),
    );
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(MockAuthService()),
        tokenStorageProvider.overrideWithValue(storage),
        hasSeenOnboardingProvider.overrideWith((_) => true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClientApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);

    container.read(onboardingFlagLoadedProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(PhoneInputScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hung profile request preserves the saved session without OTP',
      (tester) async {
    final storage = _MockTokenStorage();
    when(storage.readTokenSnapshot).thenAnswer((_) async => _session);
    when(storage.readCachedProfileJson).thenAnswer((_) async => null);
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(_HangingAuthService()),
        tokenStorageProvider.overrideWithValue(storage),
        hasSeenOnboardingProvider.overrideWith((_) => true),
        onboardingFlagLoadedProvider.overrideWith((_) => true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClientApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 1));

    expect(
      container.read(clientAuthControllerProvider),
      isA<AuthSessionRestorePending>(),
    );
    expect(find.byType(PhoneInputScreen), findsNothing);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.text('Connect to the internet and try again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final _session = AuthTokenSnapshot(
  accessToken: _jwt('access'),
  refreshToken: _jwt('refresh'),
  storageFormat: AuthTokenStorageFormat.versioned,
);

String _jwt(String marker) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode(const {
            'sub': 'auth-root-1',
            'role': 'client',
            'roleAccountId': 'client-1',
            'sid': 'session-1',
          }),
        ),
      )
      .replaceAll('=', '');
  return 'e30.$payload.$marker';
}
