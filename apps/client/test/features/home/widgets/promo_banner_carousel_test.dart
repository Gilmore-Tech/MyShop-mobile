import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/home/providers/promo_campaigns_provider.dart';
import 'package:myshop_client/src/features/home/widgets/promo_banner_carousel.dart';
import 'package:myshop_client/src/features/home/widgets/promo_details_sheet.dart';

/// 1x1 transparent PNG so `Image.network` succeeds in widget tests
/// (the default test HttpClient always returns HTTP 400).
final Uint8List _kTransparentPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND
  0x42, 0x60, 0x82,
]);

class _PngHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _kTransparentPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_kTransparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

const _bannerCampaign = ActivePromoCampaign(
  id: 'camp-1',
  name: 'August Rides',
  description: '15% off every ride in Kumasi this month.',
  termsText: 'One redemption per booking. MyShop may end this early.',
  campaignType: 'percentage_discount',
  discountValue: 15,
  maxDiscountPesewas: 1000,
  promoScope: 'ride',
  newClientsOnly: true,
  bannerUrl: 'https://cdn.example.test/banners/august.png',
  bannerPriority: 10,
);

const _noBannerCampaign = ActivePromoCampaign(
  id: 'camp-2',
  name: 'Quiet campaign',
  campaignType: 'fixed_discount',
  discountValue: 500,
  promoScope: 'both',
);

Future<void> _pumpCarousel(
  WidgetTester tester,
  List<ActivePromoCampaign> campaigns,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePromoCampaignsProvider.overrideWith((_) async => campaigns),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PromoBannerCarousel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    HttpOverrides.global = _PngHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('renders nothing when there are no campaigns', (tester) async {
    await _pumpCarousel(tester, const []);

    expect(find.byType(ListView), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when campaigns have no banner', (tester) async {
    await _pumpCarousel(tester, const [_noBannerCampaign]);

    expect(find.byType(ListView), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('renders a banner for campaigns with a bannerUrl',
      (tester) async {
    await _pumpCarousel(
      tester,
      const [_bannerCampaign, _noBannerCampaign],
    );

    expect(find.byKey(const Key('promo-banner-camp-1')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    // The banner-less campaign contributes no carousel item.
    expect(find.byKey(const Key('promo-banner-camp-2')), findsNothing);
  });

  testWidgets('tapping a banner opens the campaign details sheet',
      (tester) async {
    await _pumpCarousel(tester, const [_bannerCampaign]);

    await tester.tap(find.byKey(const Key('promo-banner-camp-1')));
    await tester.pumpAndSettle();

    expect(find.byType(PromoDetailsSheet), findsOneWidget);
    expect(find.text('August Rides'), findsOneWidget);
    expect(find.text('15% off, up to GHS 10'), findsOneWidget);
    expect(find.text('New customers only'), findsOneWidget);
    expect(
      find.text('One redemption per booking. MyShop may end this early.'),
      findsOneWidget,
    );
  });
}
