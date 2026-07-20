import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/models/vehicle_form_state.dart';
import 'package:myshop_provider/src/features/profile/widgets/vehicle_form_body.dart';

void main() {
  testWidgets('blocks submission until a vehicle category is selected',
      (tester) async {
    VehicleFormState? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VehicleFormBody(
            initialValue: const VehicleFormState(
              make: 'Toyota',
              model: 'Corolla',
              year: '2024',
              plate: 'GR-1234-24',
              color: 'Silver',
            ),
            categories: const [
              VehicleCategoryChoice(
                id: 'regular-id',
                name: 'Regular',
                description: 'Standard trips',
              ),
            ],
            submitLabel: 'Add vehicle',
            onSubmit: (value) async {
              submitted = value;
              return null;
            },
          ),
        ),
      ),
    );

    await tester.fling(
      find.byType(ListView),
      const Offset(0, -1200),
      1000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add vehicle'));
    await tester.pump();
    expect(find.text('Select at least one ride category.'), findsOneWidget);
    expect(submitted, isNull);

    await tester.tap(find.text('Regular'));
    await tester.tap(find.text('Add vehicle'));
    await tester.pump();
    expect(submitted?.rideCategoryIds, {'regular-id'});
  });

  testWidgets(
    'recovers from a strict response parse failure and allows retry',
    (tester) async {
      var submitCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VehicleFormBody(
              initialValue: const VehicleFormState(
                make: 'Toyota',
                model: 'Corolla',
                year: '2024',
                plate: 'GR-1234-24',
                color: 'Silver',
                rideCategoryIds: {'regular-id'},
              ),
              categories: const [
                VehicleCategoryChoice(
                  id: 'regular-id',
                  name: 'Regular',
                  description: 'Standard trips',
                ),
              ],
              submitLabel: 'Add vehicle',
              onSubmit: (_) async {
                submitCalls += 1;
                throw const FormatException('Unexpected vehicle response');
              },
            ),
          ),
        ),
      );

      await tester.fling(
        find.byType(ListView),
        const Offset(0, -1200),
        1000,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add vehicle'));
      await tester.pumpAndSettle();

      expect(submitCalls, 1);
      expect(find.text(vehicleSubmitFailureMessage), findsOneWidget);

      await tester.tap(find.text('Add vehicle'));
      await tester.pumpAndSettle();
      expect(submitCalls, 2);
    },
  );
}
