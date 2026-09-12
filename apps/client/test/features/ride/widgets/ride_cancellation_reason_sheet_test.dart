import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/widgets/ride_cancellation_reason_sheet.dart';

void main() {
  testWidgets('returns a selected pre-match cancellation reason',
      (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showClientRideCancellationReasonSheet(
                context,
                driverAssigned: false,
              );
            },
            child: const Text('Cancel'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The search is taking too long'));
    await tester.pumpAndSettle();

    expect(result, 'The search is taking too long');
  });

  testWidgets('requires non-empty text for a custom reason', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showClientRideCancellationReasonSheet(
                context,
                driverAssigned: true,
              );
            },
            child: const Text('Cancel'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Submit reason');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Driver could not find me');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(result, 'Driver could not find me');
  });
}
