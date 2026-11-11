import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/widgets/surge_price_indicator.dart';
import 'package:myshop_client/src/features/ride/widgets/vehicle_option_card.dart';

void main() {
  for (final surge in [false, true]) {
    testWidgets('price arrow appears only for a surged estimate ($surge)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: VehicleOptionCard(
        option: VehicleOption(
            id: 'regular',
            name: 'Regular',
            description: 'Car',
            capacityPersons: 4,
            farePesewas: 2500,
            estimatedTime: '3 min',
            isMotorcycle: false,
            surgeActive: surge,
            surgeMultiplier: surge ? 1.5 : 1),
        isSelected: true,
        onTap: () {},
      ))));
      expect(find.byType(SurgePriceIndicator),
          surge ? findsOneWidget : findsNothing);
      expect(find.text('Surge Pricing Active'), findsNothing);
      if (surge) {
        expect(find.byTooltip('Higher demand · 1.5× pricing'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
