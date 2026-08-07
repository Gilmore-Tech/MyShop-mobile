import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions capturedRequest;

  Dio buildDio(Map<String, dynamic> data) {
    final client = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {'success': true, 'data': data},
            ),
          );
        },
      ),
    );
    return client;
  }

  test('fetches active campaigns from GET /promos/active', () async {
    dio = buildDio({
      'campaigns': [
        {
          'id': 'camp-1',
          'name': 'August Rides',
          'description': '15% off every ride in Kumasi.',
          'termsText': 'One redemption per booking.',
          'campaignType': 'percentage_discount',
          'discountValue': 15,
          'maxDiscountPesewas': 1000,
          'minBookingPesewas': 2000,
          'promoScope': 'ride',
          'newClientsOnly': true,
          'startsAt': '2026-08-01T00:00:00.000Z',
          'endsAt': '2026-08-31T23:59:59.000Z',
          'bannerUrl': 'https://cdn.example.test/banners/august.png',
          'bannerPriority': 10,
          // Unknown fields must be ignored (additive contract).
          'someFutureField': {'nested': true},
        },
      ],
    });

    final campaigns = await PromoService(dio).getActiveCampaigns();

    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.path, '/promos/active');
    expect(campaigns, hasLength(1));
    final c = campaigns.single;
    expect(c.id, 'camp-1');
    expect(c.name, 'August Rides');
    expect(c.campaignType, 'percentage_discount');
    expect(c.isPercentage, isTrue);
    expect(c.discountValue, 15);
    expect(c.maxDiscountPesewas, 1000);
    expect(c.minBookingPesewas, 2000);
    expect(c.promoScope, 'ride');
    expect(c.newClientsOnly, isTrue);
    expect(c.startsAt, DateTime.utc(2026, 8, 1));
    expect(c.endsAt, DateTime.utc(2026, 8, 31, 23, 59, 59));
    expect(c.bannerUrl, 'https://cdn.example.test/banners/august.png');
    expect(c.hasBanner, isTrue);
    expect(c.bannerPriority, 10);
  });

  test('tolerates missing optional keys (old backend shape)', () async {
    dio = buildDio({
      'campaigns': [
        {'id': 'camp-2', 'name': 'GHS 5 off'},
      ],
    });

    final campaigns = await PromoService(dio).getActiveCampaigns();

    expect(campaigns, hasLength(1));
    final c = campaigns.single;
    expect(c.description, isEmpty);
    expect(c.termsText, isEmpty);
    expect(c.discountValue, 0);
    expect(c.maxDiscountPesewas, isNull);
    expect(c.minBookingPesewas, isNull);
    expect(c.newClientsOnly, isFalse);
    expect(c.startsAt, isNull);
    expect(c.endsAt, isNull);
    expect(c.bannerUrl, isNull);
    expect(c.hasBanner, isFalse);
    expect(c.bannerPriority, 0);
    // Older backends never send `audience` — those campaigns were always
    // client-targeted, so absence must default to 'client'.
    expect(c.audience, 'client');
  });

  test('parses the provider audience + commission-relief shape', () async {
    dio = buildDio({
      'campaigns': [
        {
          'id': 'camp-relief-1',
          'name': 'Driver Boost Week',
          'campaignType': 'commission_relief',
          'discountValue': 50,
          'maxDiscountPesewas': 1500,
          'audience': 'provider_driver',
        },
        {
          'id': 'camp-relief-2',
          'name': 'Artisan Relief',
          'campaignType': 'commission_relief',
          'discountValue': 100,
          'audience': 'provider_artisan',
        },
      ],
    });

    final campaigns = await PromoService(dio).getActiveCampaigns();

    expect(campaigns, hasLength(2));
    final driver = campaigns.first;
    expect(driver.audience, 'provider_driver');
    expect(driver.campaignType, 'commission_relief');
    expect(driver.isCommissionRelief, isTrue);
    expect(driver.isPercentage, isFalse);
    expect(driver.discountValue, 50);
    expect(driver.maxDiscountPesewas, 1500);
    final artisan = campaigns.last;
    expect(artisan.audience, 'provider_artisan');
    expect(artisan.maxDiscountPesewas, isNull);
  });

  test('returns empty list when the feature is off', () async {
    dio = buildDio({'campaigns': <dynamic>[]});

    expect(await PromoService(dio).getActiveCampaigns(), isEmpty);
  });

  test('drops malformed entries instead of failing the list', () async {
    dio = buildDio({
      'campaigns': [
        'not-a-map',
        {'name': 'missing id'},
        {'id': 'camp-3', 'name': 'Valid'},
      ],
    });

    final campaigns = await PromoService(dio).getActiveCampaigns();

    expect(campaigns, hasLength(1));
    expect(campaigns.single.id, 'camp-3');
  });

  test('returns empty list when data has no campaigns key', () async {
    dio = buildDio({'somethingElse': true});

    expect(await PromoService(dio).getActiveCampaigns(), isEmpty);
  });
}
