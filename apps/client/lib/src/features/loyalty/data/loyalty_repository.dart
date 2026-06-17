import 'package:api_client/api_client.dart';

import '../domain/loyalty_models.dart';

/// Repository wrapping the three loyalty-redemption endpoints behind typed
/// models so the UI never touches raw envelopes:
///
///   • `GET  /users/me`               → current points balance
///   • `GET  /loyalty/transactions`   → paginated ledger
///   • `POST /loyalty/redeem`         → apply points to an active booking
///
/// It also reads the admin-tunable redemption economics from `platform_config`
/// (`loyalty_ghs_per_point_pesewas`, `loyalty_max_redemption_percent`),
/// falling back to [LoyaltyRate.fallback] when those reads fail so the flow is
/// never blocked on a config fetch.
class LoyaltyRepository {
  LoyaltyRepository({
    required UserService userService,
    required LoyaltyService loyaltyService,
    required PlatformConfigService configService,
  })  : _userService = userService,
        _loyaltyService = loyaltyService,
        _configService = configService;

  final UserService _userService;
  final LoyaltyService _loyaltyService;
  final PlatformConfigService _configService;

  static const _kPointPesewasKey = 'loyalty_ghs_per_point_pesewas';
  static const _kMaxPercentKey = 'loyalty_max_redemption_percent';

  /// Current loyalty balance off the live profile (`client.loyaltyPointsBalance`).
  Future<int> fetchBalance() async {
    final json = await _userService.getMe();
    final profile = UserProfile.fromJson(json);
    return profile.client?.loyaltyPointsBalance ?? 0;
  }

  /// One page of the points ledger, newest first.
  Future<LoyaltyTransactionsPage> fetchTransactions({
    int page = 1,
    int limit = 20,
  }) async {
    final json =
        await _loyaltyService.getTransactions(page: page, limit: limit);
    return LoyaltyTransactionsPage.fromEnvelope(json);
  }

  /// Apply [points] of loyalty against an active booking. The returned values
  /// are authoritative — the server caps the discount, so the points spent and
  /// the discount granted may be smaller than requested.
  Future<LoyaltyRedemption> redeem({
    required int points,
    required RedeemableBookingType bookingType,
    required String bookingId,
  }) async {
    final json = await _loyaltyService.redeemPoints(
      points: points,
      bookingType: bookingType.wireValue,
      bookingId: bookingId,
    );
    return LoyaltyRedemption.fromJson(json);
  }

  /// Redemption economics. Never throws — a failed/missing config read yields
  /// [LoyaltyRate.fallback] (10 pesewas/point, 50% ceiling).
  Future<LoyaltyRate> fetchRate() async {
    try {
      final point = await _configService.getNumber(_kPointPesewasKey);
      final percent = await _configService.getNumber(_kMaxPercentKey);
      return LoyaltyRate(
        pointPesewas: point != null && point > 0
            ? point.toInt()
            : LoyaltyRate.fallback.pointPesewas,
        maxRedemptionPercent: percent != null && percent > 0
            ? percent.toInt()
            : LoyaltyRate.fallback.maxRedemptionPercent,
      );
    } catch (_) {
      return LoyaltyRate.fallback;
    }
  }
}
