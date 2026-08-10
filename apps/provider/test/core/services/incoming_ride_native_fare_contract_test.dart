import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS notification and Live Activity consume additive fare fields', () {
    final attributes = File(
      'ios/Shared/RequestOfferAttributes.swift',
    ).readAsStringSync();
    final notification = File(
      'ios/RequestNotificationContent/NotificationViewController.swift',
    ).readAsStringSync();
    final liveActivity = File(
      'ios/RequestLiveActivity/RequestLiveActivityWidget.swift',
    ).readAsStringSync();

    for (final field in const [
      'estimatedProviderEarningsPesewas',
      'prePromoFarePesewas',
      'clientPayableEstimatePesewas',
      'promoDiscountPesewas',
      'loyaltyDiscountPesewas',
      'platformDiscountPesewas',
      'promoApplied',
      'paymentMethod',
    ]) {
      expect(attributes, contains(field), reason: 'missing $field contract');
      expect(
        notification,
        contains(field),
        reason: 'notification drops $field',
      );
      expect(liveActivity, contains(field), reason: 'activity drops $field');
    }
    expect(notification, contains('ESTIMATED EARNINGS'));
    expect(notification, contains('ESTIMATED FARE'));
    expect(liveActivity, contains('estimated fare'));
    expect(liveActivity, contains('est. earnings'));
  });

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

    for (final field in const ['amountLabel', 'pricingSummary']) {
      expect(payload, contains(field));
      expect(codec, contains('offer.$field'));
      expect(card, contains('offer.$field'));
    }
    expect(codec, contains('EXTRA_AMOUNT_LABEL'));
    expect(codec, contains('EXTRA_PRICING_SUMMARY'));
  });
}
