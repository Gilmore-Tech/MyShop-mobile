import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS pricing contract keeps legacy fare and drops provider economics',
    () {
      final attributes = File(
        'ios/Shared/RequestOfferAttributes.swift',
      ).readAsStringSync();
      final notification = File(
        'ios/RequestNotificationContent/NotificationViewController.swift',
      ).readAsStringSync();
      final liveActivity = File(
        'ios/RequestLiveActivity/RequestLiveActivityWidget.swift',
      ).readAsStringSync();
      final bridge = File(
        'ios/Runner/RequestLiveActivityBridge.swift',
      ).readAsStringSync();

      for (final field in const [
        'prePromoFarePesewas',
        'clientPayableEstimatePesewas',
        'promoDiscountPesewas',
        'loyaltyDiscountPesewas',
        'platformDiscountPesewas',
        'promoApplied',
        'paymentMethod',
      ]) {
        expect(attributes, contains(field), reason: 'missing $field contract');
      }
      for (final source in [attributes, bridge, notification, liveActivity]) {
        for (final field in const [
          'commissionPesewas',
          'commissionRatePercent',
          'estimatedProviderEarningsPesewas',
          'providerEarningsPesewas',
          'netPayoutPesewas',
        ]) {
          expect(source, isNot(contains(field)));
        }
      }
      expect(attributes, contains('let farePesewas: Int?'));
      expect(notification, contains('hasCurrentContext ? legacyFare : nil'));
      expect(notification, contains('PROMO / DISCOUNT'));
      expect(notification, contains('CLIENT PRICE'));
      expect(notification, contains('ESTIMATED FARE'));
      expect(notification, contains('tripFare - clientPrice'));
      expect(liveActivity, contains('PROMO / DISCOUNT'));
      expect(liveActivity, contains('CLIENT PRICE'));
      expect(liveActivity, contains('ESTIMATED FARE'));
      expect(liveActivity, contains('hasCurrentContext'));
      expect(liveActivity, contains('tripFare - clientPrice'));
    },
  );

  test('Android intent codec preserves explicit price caption and summary', () {
    final payload = File(
      '../../packages/incoming_request_overlay/android/src/main/kotlin/'
      'com/gilmoretech/incoming_request_overlay/OfferPayload.kt',
    ).readAsStringSync();
    final codec = File(
      '../../packages/incoming_request_overlay/android/src/main/kotlin/'
      'com/gilmoretech/incoming_request_overlay/OfferPayloadCodec.kt',
    ).readAsStringSync();
    final card = File(
      '../../packages/incoming_request_overlay/android/src/main/kotlin/'
      'com/gilmoretech/incoming_request_overlay/OfferCardView.kt',
    ).readAsStringSync();
    final presenter = File(
      'lib/src/core/services/incoming_request_overlay_presenter.dart',
    ).readAsStringSync();
    final fareCopy = File(
      'lib/src/core/utils/incoming_ride_fare_copy.dart',
    ).readAsStringSync();

    for (final field in const ['amountLabel', 'pricingSummary']) {
      expect(payload, contains(field));
      expect(codec, contains('offer.$field'));
      expect(card, contains('offer.$field'));
    }
    expect(codec, contains('EXTRA_AMOUNT_LABEL'));
    expect(codec, contains('EXTRA_PRICING_SUMMARY'));
    expect(presenter, contains('pricingSummary: fare.nativePricingSummary'));
    expect(fareCopy, contains("'PROMO / DISCOUNT'"));
    expect(fareCopy, contains("'CLIENT PRICE'"));
    expect(fareCopy, contains(".join('\\n')"));
    expect(card, contains('maxLines = 3'));
  });
}
