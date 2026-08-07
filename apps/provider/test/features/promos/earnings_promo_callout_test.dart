import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/promos/providers/promo_campaigns_provider.dart';
import 'package:myshop_provider/src/features/promos/widgets/earnings_promo_callout.dart';
import 'package:myshop_provider/src/features/promos/widgets/promo_details_sheet.dart';

final _reliefWithEndDate = ActivePromoCampaign(
  id: 'camp-relief-1',
  name: 'Driver Boost Week',
  campaignType: 'commission_relief',
  discountValue: 50,
  maxDiscountPesewas: 1500,
  audience: 'provider_driver',
  endsAt: DateTime(2026, 8, 31, 23, 59),
);

const _biggerRelief = ActivePromoCampaign(
  id: 'camp-relief-2',
  name: 'Mega Relief',
  campaignType: 'commission_relief',
  discountValue: 75,
  audience: 'provider_driver',
);

const _clientStyleCampaign = ActivePromoCampaign(
  id: 'camp-client-1',
  name: 'Client discount',
  campaignType: 'percentage_discount',
  discountValue: 15,
);

Future<void> _pumpCallout(
  WidgetTester tester,
  List<ActivePromoCampaign> campaigns,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePromoCampaignsProvider.overrideWith((_) async => campaigns),
      ],
      child: const MaterialApp(
        home: Scaffold(body: EarningsPromoCallout()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders nothing when there are no campaigns', (tester) async {
    await _pumpCallout(tester, const []);

    expect(find.byKey(const Key('earnings-promo-callout')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when no campaign is commission relief',
      (tester) async {
    await _pumpCallout(tester, const [_clientStyleCampaign]);

    expect(find.byKey(const Key('earnings-promo-callout')), findsNothing);
  });

  testWidgets('shows the relief callout with percent and end date',
      (tester) async {
    await _pumpCallout(tester, [_reliefWithEndDate]);

    expect(find.byKey(const Key('earnings-promo-callout')), findsOneWidget);
    expect(
      find.text('Active promo: 50% commission relief until 31 Aug 2026'),
      findsOneWidget,
    );
  });

  testWidgets('picks the highest-relief campaign', (tester) async {
    await _pumpCallout(tester, [_reliefWithEndDate, _biggerRelief]);

    expect(
      find.text('Active promo: 75% commission relief'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the callout opens the details sheet', (tester) async {
    await _pumpCallout(tester, [_reliefWithEndDate]);

    await tester.tap(find.byKey(const Key('earnings-promo-callout')));
    await tester.pumpAndSettle();

    expect(find.byType(PromoDetailsSheet), findsOneWidget);
    expect(find.text('Driver Boost Week'), findsOneWidget);
    expect(
      find.text('50% commission relief, up to GHS 15 per booking'),
      findsOneWidget,
    );
  });
}
