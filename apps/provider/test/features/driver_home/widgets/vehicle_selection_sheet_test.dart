import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/driver_home/widgets/online_offline_toggle.dart';

void main() {
  testWidgets(
    'shows an ineligible vehicle and every document blocker instead of hiding the car',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VehicleSelectionSheet(
              preflight: ProviderVehiclePreflight(
                activeVehicleId: null,
                onlineStatus: 'offline',
                legacyBackfillRequired: false,
                vehicles: [
                  ProviderVehicleSummary(
                    id: 'vehicle-1',
                    make: 'Toyota',
                    model: 'Corolla',
                    year: 2020,
                    plate: 'GR-1234-20',
                    color: 'Silver',
                    isActive: true,
                    eligible: false,
                    reasonCodes: [
                      'VEHICLE_DOCUMENT_EXPIRY_MISSING_ROADWORTHINESS',
                      'VEHICLE_DOCUMENT_MISSING_INSURANCE',
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Toyota Corolla'), findsOneWidget);
      expect(find.textContaining('GR-1234-20'), findsOneWidget);
      expect(
        find.text(
          'No vehicle can go online yet. Review each vehicle’s blockers below.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'The approved roadworthiness certificate needs an expiry date from support.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Upload this vehicle’s insurance certificate.'),
        findsOneWidget,
      );

      final choice = tester.widget<RadioListTile<String>>(
        find.byType(RadioListTile<String>),
      );
      expect(choice.enabled, isFalse);
      final useVehicle = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Use this vehicle'),
      );
      expect(useVehicle.onPressed, isNull);
    },
  );
}
