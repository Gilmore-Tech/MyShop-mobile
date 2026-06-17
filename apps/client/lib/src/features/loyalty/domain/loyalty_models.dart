import 'package:api_client/api_client.dart' show ApiException;

/// Booking kinds that accept a loyalty redemption. Wire value matches the
/// backend `bookingType` enum on `POST /v1/loyalty/redeem`.
enum RedeemableBookingType {
  ride,
  job;

  String get wireValue => name; // 'ride' | 'job'

  String get label => switch (this) {
        RedeemableBookingType.ride => 'ride',
        RedeemableBookingType.job => 'job',
      };
}

/// Format an integer pesewas amount as Ghana cedis: `GHS 12.50`.
///
/// Money is always integer pesewas end-to-end (100 pesewas = GHS 1). We only
/// divide by 100 for display, never for arithmetic — see CLAUDE.md money rule.
String formatGhsFromPesewas(int pesewas) {
  final ghs = pesewas / 100;
  return 'GHS ${ghs.toStringAsFixed(2)}';
}

/// Runtime redemption economics, sourced from `platform_config` with safe
/// fallbacks. The point value and the discount ceiling are admin-tunable, so
/// the sheet reads them at open time rather than hard-coding.
class LoyaltyRate {
  const LoyaltyRate({
    required this.pointPesewas,
    required this.maxRedemptionPercent,
  });

  /// Default 10 pesewas/point (GHS 0.10) and a 50% fare ceiling — these mirror
  /// the backend config defaults (`loyalty_ghs_per_point_pesewas`,
  /// `loyalty_max_redemption_percent`) so the UI degrades gracefully when the
  /// `/config` reads fail (offline, first launch).
  static const fallback =
      LoyaltyRate(pointPesewas: 10, maxRedemptionPercent: 50);

  /// Pesewas one point is worth at redemption.
  final int pointPesewas;

  /// Hard cap on the discount as a percentage of the fare (e.g. 50 = 50%).
  final int maxRedemptionPercent;

  /// Largest discount (pesewas) allowed against [farePesewas]. Integer math
  /// only — never float money.
  int maxDiscountPesewas(int farePesewas) =>
      (farePesewas * maxRedemptionPercent) ~/ 100;

  /// Most points the client could spend on [farePesewas], capped by both the
  /// discount ceiling and how many whole points fit into that ceiling.
  int maxRedeemablePoints(int farePesewas, int balance) {
    if (pointPesewas <= 0) return 0;
    final byFare = maxDiscountPesewas(farePesewas) ~/ pointPesewas;
    final capped = byFare < balance ? byFare : balance;
    return capped < 0 ? 0 : capped;
  }

  /// Local, optimistic discount preview for [points] before the server
  /// confirms. Reconcile against [LoyaltyRedemption.discountPesewas].
  int previewDiscountPesewas(int points) => points * pointPesewas;
}

/// Result of `POST /v1/loyalty/redeem`. Always trust these values over the
/// requested points — the server caps the discount at 50% of fare, so the
/// points actually spent and the discount granted may be smaller than asked.
class LoyaltyRedemption {
  const LoyaltyRedemption({
    required this.pointsRedeemed,
    required this.discountPesewas,
    required this.newBalance,
  });

  factory LoyaltyRedemption.fromJson(Map<String, dynamic> json) {
    return LoyaltyRedemption(
      // `pointsRedeemed` is the authoritative spend; some older builds of the
      // endpoint omit it, so fall back to 0 rather than throwing.
      pointsRedeemed: (json['pointsRedeemed'] as num?)?.toInt() ?? 0,
      discountPesewas: (json['discountPesewas'] as num?)?.toInt() ?? 0,
      newBalance: (json['newBalance'] as num?)?.toInt() ?? 0,
    );
  }

  /// Points actually deducted (may be less than requested if capped).
  final int pointsRedeemed;

  /// Discount applied to the fare, in pesewas.
  final int discountPesewas;

  /// Remaining loyalty balance after the redemption.
  final int newBalance;

  String get discountDisplay => formatGhsFromPesewas(discountPesewas);
}

/// One row of the `/v1/loyalty/transactions` ledger.
class LoyaltyTransaction {
  const LoyaltyTransaction({
    required this.transactionType,
    required this.points,
    required this.balanceAfter,
    required this.createdAt,
    this.bookingType,
    this.bookingId,
    this.description,
  });

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> json) {
    return LoyaltyTransaction(
      transactionType: json['transactionType'] as String? ?? '',
      // Signed: positive for earn, negative for redeem/expire.
      points: (json['points'] as num?)?.toInt() ?? 0,
      balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
      bookingType: json['bookingType'] as String?,
      bookingId: json['bookingId'] as String?,
      description: (json['description'] as String?)?.trim(),
      createdAt: json['createdAt'] as String?,
    );
  }

  final String transactionType;
  final int points;
  final int balanceAfter;
  final String? bookingType;
  final String? bookingId;
  final String? description;
  final String? createdAt;

  bool get isEarn => points >= 0;

  /// Human label, preferring the backend description when present.
  String get label {
    final desc = description;
    if (desc != null && desc.isNotEmpty) return desc;
    return switch (transactionType) {
      'earned_ride' => 'Ride completed',
      'earned_job' => 'Job completed',
      'earned_referral' => 'Referral bonus',
      'redeemed' => 'Points redeemed',
      'expired' => 'Points expired',
      'adjusted' => 'Balance adjusted',
      _ => 'Transaction',
    };
  }

  /// `+5` / `-100` for direct rendering.
  String get pointsDisplay => '${isEarn ? '+' : '-'}${points.abs()}';

  DateTime? get createdAtDate =>
      createdAt == null ? null : DateTime.tryParse(createdAt!);
}

/// A page of ledger rows plus its pagination metadata.
class LoyaltyTransactionsPage {
  const LoyaltyTransactionsPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  factory LoyaltyTransactionsPage.fromEnvelope(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final meta = json['meta'] as Map<String, dynamic>?;
    return LoyaltyTransactionsPage(
      items: rawItems.map(LoyaltyTransaction.fromJson).toList(),
      page: (meta?['page'] as num?)?.toInt() ?? 1,
      totalPages: (meta?['totalPages'] as num?)?.toInt() ?? 1,
    );
  }

  final List<LoyaltyTransaction> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

/// Maps a redemption failure to friendly, user-facing copy.
///
/// [balance] is the client's current point balance — used to personalise the
/// "you only have N points" message. Unknown errors fall back to a generic
/// retry message; network errors surface their own copy.
String redeemErrorMessage(Object error, {required int balance}) {
  if (error is ApiException) {
    switch (error.errorCode) {
      case 'INSUFFICIENT_LOYALTY_POINTS':
        final n = balance;
        return 'You only have $n ${n == 1 ? 'point' : 'points'}.';
      case 'BOOKING_ALREADY_REDEEMED':
        return 'Points already applied to this booking.';
      case 'REDEMPTION_AMOUNT_TOO_SMALL':
        return "That's too few points to apply a discount.";
      case 'ACTIVE_RIDE_NOT_FOUND':
      case 'ACTIVE_JOB_NOT_FOUND':
        return 'This booking is no longer active.';
      case 'CLIENT_PROFILE_REQUIRED':
        return 'Complete your client profile to redeem points.';
    }
    if (error.isNetworkError) return error.message;
  }
  return "Couldn't apply your points. Please try again.";
}
