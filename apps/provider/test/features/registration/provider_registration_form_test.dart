import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/registration/providers/categories_provider.dart';
import 'package:myshop_provider/src/features/registration/widgets/artisan_business_step.dart';
import 'package:myshop_provider/src/features/registration/widgets/artisan_profile_step.dart';
import 'package:myshop_provider/src/features/registration/widgets/driver_profile_step.dart';
import 'package:myshop_provider/src/features/registration/widgets/registration_step_scaffold.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('provider profiles omit unsaved Ghana Card input',
      (tester) async {
    for (final profile in const <Widget>[
      DriverProfileStep(),
      ArtisanProfileStep(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: Scaffold(body: profile)),
        ),
      );

      expect(find.text('Email'), findsOneWidget);
      expect(find.textContaining('Ghana Card'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('artisan business step omits fields not sent to registration',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((_) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ArtisanBusinessStep()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Business name'), findsOneWidget);
    expect(find.text('Primary trade'), findsNothing);
    expect(find.text('Years of experience'), findsNothing);
  });

  testWidgets('registration footer disables Continue when step is invalid',
      (tester) async {
    var continueCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationStepScaffold(
          steps: const [
            MyShopStepItem(label: 'Profile', icon: Icons.person_outline),
          ],
          currentIndex: 0,
          title: 'Your profile',
          subtitle: 'Tell us about yourself',
          onContinue: () => continueCalls += 1,
          continueLabel: 'Continue',
          isContinueEnabled: false,
          child: const SizedBox.shrink(),
        ),
      ),
    );

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(continueCalls, 0);
  });
}
