import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('converts explicit work duration units to minutes', () {
    expect(
      artisanWorkDurationMinutes(
        quantity: 4,
        unit: ArtisanWorkDurationUnit.hours,
      ),
      240,
    );
    expect(
      artisanWorkDurationMinutes(
        quantity: 15,
        unit: ArtisanWorkDurationUnit.days,
      ),
      21600,
    );
  });

  testWidgets(
    'counteroffer owns its controllers and returns the selected day duration',
    (tester) async {
      ArtisanCounterofferProposal? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showArtisanCounterofferDialog(
                    context,
                    initialAmountPesewas: 12000,
                    initialDurationMinutes: 90,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('120.00'), findsOneWidget);

      await tester.tap(find.text('Days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 days').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send counteroffer'));
      await tester.pumpAndSettle();

      expect(result?.amountPesewas, 12000);
      expect(result?.durationMinutes, 3 * 24 * 60);
      expect(tester.takeException(), isNull);
    },
  );
}
