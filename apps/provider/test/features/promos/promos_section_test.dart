import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/promos/providers/promo_campaigns_provider.dart';
import 'package:myshop_provider/src/features/promos/widgets/promo_details_sheet.dart';
import 'package:myshop_provider/src/features/promos/widgets/promos_section.dart';

import '../../support/png_http_overrides.dart';

const _bannerReliefCampaign = ActivePromoCampaign(
  id: 'camp-relief-1',
  name: 'Driver Boost Week',
  description: 'Keep more of your fares all week long.',
  termsText: 'Applies to completed bookings only.',
  campaignType: 'commission_relief',
  discountValue: 50,
  maxDiscountPesewas: 1500,
  newClientsOnly: true,
  audience: 'provider_driver',
  bannerUrl: 'https://cdn.example.test/banners/driver-boost.png',
  bannerPriority: 10,
);

const _noBannerReliefCampaign = ActivePromoCampaign(
  id: 'camp-relief-2',
  name: 'Quiet relief',
  campaignType: 'commission_relief',
  discountValue: 25,
  audience: 'provider_artisan',
);

Future<void> _pumpSection(
  WidgetTester tester,
  List<ActivePromoCampaign> campaigns,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePromoCampaignsProvider.overrideWith((_) async => campaigns),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PromosSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    HttpOverrides.global = PngHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('renders nothing when there are no campaigns', (tester) async {
    await _pumpSection(tester, const []);

    expect(find.text('PROMOS'), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when campaigns have no banner', (tester) async {
    await _pumpSection(tester, const [_noBannerReliefCampaign]);

    expect(find.text('PROMOS'), findsNothing);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('renders header + banner for a bannered relief campaign',
      (tester) async {
    await _pumpSection(
      tester,
      const [_bannerReliefCampaign, _noBannerReliefCampaign],
    );

    expect(find.text('PROMOS'), findsOneWidget);
    expect(
      find.byKey(const Key('promo-banner-camp-relief-1')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
    // The banner-less campaign contributes no carousel item.
    expect(find.byKey(const Key('promo-banner-camp-relief-2')), findsNothing);
  });

  testWidgets('tapping a banner opens the relief details sheet',
      (tester) async {
    await _pumpSection(tester, const [_bannerReliefCampaign]);

    await tester.tap(find.byKey(const Key('promo-banner-camp-relief-1')));
    await tester.pumpAndSettle();

    expect(find.byType(PromoDetailsSheet), findsOneWidget);
    expect(find.text('Driver Boost Week'), findsOneWidget);
    expect(
      find.text('50% commission relief, up to GHS 15 per booking'),
      findsOneWidget,
    );
    expect(
      find.text(
        'You keep more of every fare — the platform takes a smaller cut',
      ),
      findsOneWidget,
    );
    expect(find.text('New providers only'), findsOneWidget);
    expect(find.text('Applies to completed bookings only.'), findsOneWidget);
  });
}
