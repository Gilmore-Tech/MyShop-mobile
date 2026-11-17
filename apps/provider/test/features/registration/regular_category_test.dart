import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/registration/providers/registration_controller.dart';
import 'package:myshop_provider/src/features/registration/providers/ride_categories_provider.dart';
import 'package:myshop_provider/src/features/registration/widgets/driver_categories_step.dart';

void main() {
  test(
      'Regular survives explicit empty selections, copies, and Comfort-only drafts',
      () {
    expect(DriverRegistrationDraft().rideCategories, ['regular']);
    final draft = DriverRegistrationDraft(rideCategories: ['comfort']);
    expect(draft.rideCategories, ['regular', 'comfort']);
    expect(draft.copyWith(rideCategories: []).rideCategories, ['regular']);
    expect(
        DriverRegistrationDraft(rideCategories: ['regular', 'regular'])
            .rideCategories,
        ['regular']);
  });

  testWidgets('Regular cannot be deselected while Comfort can be toggled',
      (tester) async {
    final container = ProviderContainer(overrides: [
      rideCategoryOptionsProvider.overrideWith((ref, region) async => const [
            RideCategoryOption(
                slug: 'regular', name: 'Regular', description: ''),
            RideCategoryOption(
                slug: 'comfort', name: 'Comfort', description: ''),
          ]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            const MaterialApp(home: Scaffold(body: DriverCategoriesStep()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regular (required)'));
    expect(
        container.read(driverRegistrationProvider).rideCategories, ['regular']);
    await tester.tap(find.text('Comfort'));
    await tester.pump();
    expect(container.read(driverRegistrationProvider).rideCategories,
        ['regular', 'comfort']);
    await tester.tap(find.text('Comfort'));
    expect(
        container.read(driverRegistrationProvider).rideCategories, ['regular']);
  });
}
