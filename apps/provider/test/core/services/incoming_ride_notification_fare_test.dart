import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';

void main() {
  test('ride fallback includes positive toll reimbursement exactly once', () {
    final body = privacySafeRequestBody('ride_request', {
      'offerPayload': jsonEncode({
        'prePromoFarePesewas': 4500,
        'clientPayableEstimatePesewas': 4500,
        'toll': {'label': 'Airport toll', 'amountPesewas': 500},
      }),
    });

    expect(body, contains('Airport toll (100% to you) GHS 5.00'));
    expect(RegExp('toll', caseSensitive: false).allMatches(body), hasLength(1));
    expect(body, contains('Est. full fare GHS 45.00'));
  });

  test('ride fallback has no toll wording for absent or zero charge', () {
    for (final payload in <Map<String, dynamic>>[
      {'prePromoFarePesewas': 4000, 'clientPayableEstimatePesewas': 4000},
      {
        'prePromoFarePesewas': 4000,
        'clientPayableEstimatePesewas': 4000,
        'toll': {'label': 'Airport toll', 'amountPesewas': 0},
      },
    ]) {
      final body = privacySafeRequestBody('ride_request', {
        'offerPayload': jsonEncode(payload),
      });
      expect(body.toLowerCase(), isNot(contains('toll')));
    }
  });

  test('promo fallback shows three prices and reconciles a stale discount', () {
    final body = privacySafeRequestBody('ride_request', {
      'offerPayload': jsonEncode({
        'estimatedFarePesewas': 600,
        'estimatedProviderEarningsPesewas': 800,
        'prePromoFarePesewas': 1000,
        'clientPayableEstimatePesewas': 600,
        'platformDiscountPesewas': 999,
        'promoApplied': true,
        'paymentMethod': 'cash',
        'distanceKm': 4.2,
      }),
    });

    expect(
      body,
      'Est. full fare GHS 10.00 · Promo / discount - GHS 4.00 · '
      'Client price GHS 6.00 · 4.2 km · Unlock to view route.',
    );
    expect(body.toLowerCase(), isNot(contains('earnings')));
  });

  test('legacy fallback notification never calls rider quote earnings', () {
    final body = privacySafeRequestBody('ride_request', {
      'estimatedFarePesewas': '600',
      'estimatedProviderEarningsPesewas': '800',
      'distanceKm': '2.5',
    });

    expect(body, contains('Estimated fare GHS 6.00'));
    expect(body, isNot(contains('earnings')));
  });

  test(
    'fully subsidised fallback preserves a legitimate zero client price',
    () {
      final body = privacySafeRequestBody('ride_request', {
        'estimatedProviderEarningsPesewas': '1144',
        'prePromoFarePesewas': '1430',
        'clientPayableEstimatePesewas': '0',
        'platformDiscountPesewas': '1430',
        'paymentMethod': 'momo_mtn',
      });

      expect(body, contains('Promo / discount - GHS 14.30'));
      expect(body, contains('Client price GHS 0.00'));
      expect(body.toLowerCase(), isNot(contains('earnings')));
    },
  );

  test('non-promo fallback still shows an explicit zero discount', () {
    final body = privacySafeRequestBody('ride_request', {
      'prePromoFarePesewas': 1000,
      'clientPayableEstimatePesewas': 1000,
      'platformDiscountPesewas': 0,
    });

    expect(body, contains('Est. full fare GHS 10.00'));
    expect(body, contains('Promo / discount - GHS 0.00'));
    expect(body, contains('Client price GHS 10.00'));
  });

  test('local extras strip every provider-economic field at every depth', () {
    const economics = <String>[
      'commissionPesewas',
      'commission_pesewas',
      'commissionRatePercent',
      'commission_rate_percent',
      'estimatedProviderEarningsPesewas',
      'estimated_provider_earnings_pesewas',
      'providerEarningsPesewas',
      'provider_earnings_pesewas',
      'netPayoutPesewas',
      'net_payout_pesewas',
    ];
    final extras = privacySafeRequestExtras('ride_request', {
      'type': 'ride_request',
      'rideId': 'ride-1',
      for (final key in economics) key: 'top-level',
      'offerPayload': jsonEncode({
        'prePromoFarePesewas': 1000,
        for (final key in economics) key: 800,
        'nested': {for (final key in economics) key: 700, 'safe': 'kept'},
      }),
    });
    final offer = jsonDecode(extras['offerPayload']!) as Map<String, dynamic>;

    expect(extras['rideId'], 'ride-1');
    expect(offer['prePromoFarePesewas'], 1000);
    for (final key in economics) {
      expect(extras, isNot(contains(key)));
      expect(extras['offerPayload'], isNot(contains(key)));
    }
    expect(offer['nested'], {'safe': 'kept'});
  });

  test('malformed economic JSON is not forwarded to the OS payload', () {
    final extras = privacySafeRequestExtras('ride_request', {
      'rideId': 'ride-1',
      'offerPayload': '{"commissionPesewas":123',
    });

    expect(extras['rideId'], 'ride-1');
    expect(extras, isNot(contains('offerPayload')));
  });
}
