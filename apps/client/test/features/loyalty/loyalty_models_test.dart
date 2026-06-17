import 'package:api_client/api_client.dart';
import 'package:myshop_client/src/features/loyalty/domain/loyalty_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatGhsFromPesewas', () {
    test('formats pesewas as GHS with 2 decimals', () {
      expect(formatGhsFromPesewas(2500), 'GHS 25.00');
      expect(formatGhsFromPesewas(10), 'GHS 0.10');
      expect(formatGhsFromPesewas(0), 'GHS 0.00');
      expect(formatGhsFromPesewas(199), 'GHS 1.99');
    });
  });

  group('LoyaltyRate', () {
    const rate = LoyaltyRate(pointPesewas: 10, maxRedemptionPercent: 50);

    test('maxDiscountPesewas caps at the configured percent of fare', () {
      expect(rate.maxDiscountPesewas(5000), 2500); // 50% of 5000
      expect(rate.maxDiscountPesewas(0), 0);
    });

    test('maxRedeemablePoints is bounded by the fare ceiling', () {
      // 50% of 5000 = 2500 pesewas → 250 points at 10 pesewas/point.
      expect(rate.maxRedeemablePoints(5000, 1000), 250);
    });

    test('maxRedeemablePoints is bounded by the balance', () {
      // Ceiling allows 250, but the client only has 100 points.
      expect(rate.maxRedeemablePoints(5000, 100), 100);
    });

    test('maxRedeemablePoints is never negative', () {
      expect(rate.maxRedeemablePoints(0, 500), 0);
    });

    test('previewDiscountPesewas multiplies points by point value', () {
      expect(rate.previewDiscountPesewas(250), 2500);
      expect(rate.previewDiscountPesewas(0), 0);
    });

    test('guards against a zero point value', () {
      const broken = LoyaltyRate(pointPesewas: 0, maxRedemptionPercent: 50);
      expect(broken.maxRedeemablePoints(5000, 500), 0);
    });

    test('fallback mirrors backend defaults', () {
      expect(LoyaltyRate.fallback.pointPesewas, 10);
      expect(LoyaltyRate.fallback.maxRedemptionPercent, 50);
    });
  });

  group('LoyaltyRedemption.fromJson', () {
    test('parses all fields', () {
      final r = LoyaltyRedemption.fromJson({
        'pointsRedeemed': 250,
        'discountPesewas': 2500,
        'newBalance': 250,
      });
      expect(r.pointsRedeemed, 250);
      expect(r.discountPesewas, 2500);
      expect(r.newBalance, 250);
      expect(r.discountDisplay, 'GHS 25.00');
    });

    test('tolerates a missing pointsRedeemed field', () {
      final r = LoyaltyRedemption.fromJson({
        'discountPesewas': 2500,
        'newBalance': 250,
      });
      expect(r.pointsRedeemed, 0);
      expect(r.discountPesewas, 2500);
    });
  });

  group('LoyaltyTransaction', () {
    test('parses a signed earn entry', () {
      final t = LoyaltyTransaction.fromJson({
        'transactionType': 'earned_ride',
        'points': 5,
        'balanceAfter': 105,
        'bookingType': 'ride',
        'bookingId': 'r1',
        'createdAt': '2026-06-01T10:00:00.000Z',
      });
      expect(t.isEarn, isTrue);
      expect(t.pointsDisplay, '+5');
      expect(t.label, 'Ride completed');
    });

    test('parses a signed redeem entry and prefers description', () {
      final t = LoyaltyTransaction.fromJson({
        'transactionType': 'redeemed',
        'points': -100,
        'balanceAfter': 5,
        'description': 'Redeemed on ride',
      });
      expect(t.isEarn, isFalse);
      expect(t.pointsDisplay, '-100');
      expect(t.label, 'Redeemed on ride');
    });
  });

  group('LoyaltyTransactionsPage.fromEnvelope', () {
    test('reads items and pagination meta', () {
      final page = LoyaltyTransactionsPage.fromEnvelope({
        'items': [
          {'transactionType': 'earned_ride', 'points': 5, 'balanceAfter': 5},
        ],
        'meta': {'page': 1, 'limit': 20, 'total': 1, 'totalPages': 3},
      });
      expect(page.items, hasLength(1));
      expect(page.page, 1);
      expect(page.totalPages, 3);
      expect(page.hasMore, isTrue);
    });

    test('defaults to a single page when meta is absent', () {
      final page = LoyaltyTransactionsPage.fromEnvelope({'items': []});
      expect(page.hasMore, isFalse);
    });
  });

  group('redeemErrorMessage', () {
    ApiException err(String code, {int status = 400}) =>
        ApiException(message: 'x', statusCode: status, errorCode: code);

    test('INSUFFICIENT_LOYALTY_POINTS names the balance', () {
      expect(
        redeemErrorMessage(err('INSUFFICIENT_LOYALTY_POINTS'), balance: 42),
        'You only have 42 points.',
      );
      expect(
        redeemErrorMessage(err('INSUFFICIENT_LOYALTY_POINTS'), balance: 1),
        'You only have 1 point.',
      );
    });

    test('BOOKING_ALREADY_REDEEMED', () {
      expect(
        redeemErrorMessage(err('BOOKING_ALREADY_REDEEMED'), balance: 0),
        'Points already applied to this booking.',
      );
    });

    test('REDEMPTION_AMOUNT_TOO_SMALL', () {
      expect(
        redeemErrorMessage(err('REDEMPTION_AMOUNT_TOO_SMALL'), balance: 0),
        "That's too few points to apply a discount.",
      );
    });

    test('ACTIVE_RIDE_NOT_FOUND / ACTIVE_JOB_NOT_FOUND', () {
      expect(
        redeemErrorMessage(err('ACTIVE_RIDE_NOT_FOUND', status: 404),
            balance: 0),
        'This booking is no longer active.',
      );
      expect(
        redeemErrorMessage(err('ACTIVE_JOB_NOT_FOUND', status: 404),
            balance: 0),
        'This booking is no longer active.',
      );
    });

    test('CLIENT_PROFILE_REQUIRED', () {
      expect(
        redeemErrorMessage(err('CLIENT_PROFILE_REQUIRED', status: 403),
            balance: 0),
        'Complete your client profile to redeem points.',
      );
    });

    test('falls back to a generic message for unknown errors', () {
      expect(
        redeemErrorMessage(Exception('boom'), balance: 0),
        "Couldn't apply your points. Please try again.",
      );
    });

    test('surfaces network error copy', () {
      expect(
        redeemErrorMessage(
            const NetworkException(message: 'No internet connection.'),
            balance: 0),
        'No internet connection.',
      );
    });
  });
}
