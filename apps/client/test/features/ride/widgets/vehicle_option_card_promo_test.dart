import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/widgets/vehicle_option_card.dart';

const _promoOption = VehicleOption(
  id: 'regular',
  name: 'Regular',
  description: 'Everyday rides',
  capacityPersons: 4,
  // Already discounted by the backend — the promo fare.
  farePesewas: 1700,
  estimatedTime: '4 min',
  isMotorcycle: false,
  promoName: 'August Rides',
  promoOriginalFarePesewas: 2000,
);

const _plainOption = VehicleOption(
  id: 'comfort',
  name: 'Comfort',
  description: 'Newer cars',
  capacityPersons: 4,
  farePesewas: 2500,
  estimatedTime: '6 min',
  isMotorcycle: false,
);

Future<void> _pumpCard(WidgetTester tester, VehicleOption option) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VehicleOptionCard(
          option: option,
          isSelected: false,
          onTap: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'promo category shows the original fare struck through next to the '
      'promo fare, plus the campaign tag', (tester) async {
    await _pumpCard(tester, _promoOption);

    final original = tester.widget<Text>(find.text('GH₵ 20.00'));
    expect(original.style?.decoration, TextDecoration.lineThrough);

    final promoFare = tester.widget<Text>(find.text('GH₵ 17.00'));
    expect(promoFare.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(promoFare.style?.fontWeight, FontWeight.w800);

    expect(find.text('August Rides'), findsOneWidget);
  });

  testWidgets('category without promo renders the single fare unchanged',
      (tester) async {
    await _pumpCard(tester, _plainOption);

    expect(find.text('GH₵ 25.00'), findsOneWidget);
    final fare = tester.widget<Text>(find.text('GH₵ 25.00'));
    expect(fare.style?.decoration, isNull);
    expect(fare.style?.fontWeight, FontWeight.w700);
  });

  testWidgets(
      'promo metadata with no real saving falls back to the plain price '
      '(never strike through an identical fare)', (tester) async {
    const samePrice = VehicleOption(
      id: 'regular',
      name: 'Regular',
      description: 'Everyday rides',
      capacityPersons: 4,
      farePesewas: 2000,
      estimatedTime: '4 min',
      isMotorcycle: false,
      promoName: 'August Rides',
      promoOriginalFarePesewas: 2000,
    );
    await _pumpCard(tester, samePrice);

    expect(find.text('GH₵ 20.00'), findsOneWidget);
    final fare = tester.widget<Text>(find.text('GH₵ 20.00'));
    expect(fare.style?.decoration, isNull);
    expect(find.text('August Rides'), findsNothing);
  });
}
