import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';

void main() {
  test('promo fallback notification distinguishes every current quote', () {
    final body = privacySafeRequestBody('ride_request', {
      'offerPayload': jsonEncode({
        'estimatedFarePesewas': 600,
        'estimatedProviderEarningsPesewas': 800,
        'prePromoFarePesewas': 1000,
        'clientPayableEstimatePesewas': 600,
        'platformDiscountPesewas': 400,
        'promoApplied': true,
        'paymentMethod': 'cash',
        'distanceKm': 4.2,
      }),
    });

    expect(body, contains('Est. earnings GHS 8.00'));
    expect(body, contains('Est. full fare GHS 10.00'));
    expect(body, contains('Rider quote · cash GHS 6.00'));
    expect(body, contains('MyShop covers GHS 4.00'));
  });

  test('legacy fallback notification never calls rider quote earnings', () {
    final body = privacySafeRequestBody('ride_request', {
      'estimatedFarePesewas': '600',
      'distanceKm': '2.5',
    });

    expect(body, contains('Estimated fare GHS 6.00'));
    expect(body, isNot(contains('earnings')));
  });

  test('fully subsidised fallback notification includes zero rider quote', () {
    final body = privacySafeRequestBody('ride_request', {
      'estimatedProviderEarningsPesewas': '1144',
      'prePromoFarePesewas': '1430',
      'clientPayableEstimatePesewas': '0',
      'platformDiscountPesewas': '1430',
      'paymentMethod': 'momo_mtn',
    });

    expect(body, contains('Rider quote · in app GHS 0.00'));
    expect(body, contains('MyShop covers GHS 14.30'));
  });
}
