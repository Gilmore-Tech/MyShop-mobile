import 'dart:async';

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
  Future<UserProfile> getMe() => Completer<UserProfile>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('waits for preferences, then leaves splash with no session',
      (tester) async {
    final storage = _MockTokenStorage();
    when(storage.readAccessToken).thenAnswer((_) async => null);
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

  testWidgets('hung profile request cannot strand the Flutter splash',
      (tester) async {
    final storage = _MockTokenStorage();
    when(storage.readAccessToken).thenAnswer((_) async => 'stale-token');
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

    expect(container.read(clientAuthControllerProvider),
        isA<AuthUnauthenticated>());
    expect(find.byType(PhoneInputScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
