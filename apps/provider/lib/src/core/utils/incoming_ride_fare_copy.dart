import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';

/// Canonical, pre-acceptance money fields for an incoming ride offer.
///
/// [legacyEstimatedFarePesewas] is deliberately kept separate: older servers
/// used `estimatedFarePesewas` for the rider's post-discount quote. It must
/// never be relabelled as provider earnings.
@immutable
class IncomingRideFareSnapshot {
  const IncomingRideFareSnapshot({
    this.prePromoFarePesewas,
    this.clientPayableEstimatePesewas,
    this.promoDiscountPesewas,
    this.loyaltyDiscountPesewas,
    this.platformDiscountPesewas,
    this.promoApplied = false,
    this.legacyEstimatedFarePesewas,
  });

  factory IncomingRideFareSnapshot.fromRide(Ride ride) {
    final explicitClientPayable =
        ride.clientPayableEstimatePesewas ?? ride.collectFromClientPesewas;
    final hasCanonicalOfferContext = ride.prePromoFarePesewas != null ||
        explicitClientPayable != null ||
        ride.promoDiscountPesewas != null ||
        ride.loyaltyDiscountPesewas != null ||
        ride.platformDiscountPesewas != null;
    return IncomingRideFareSnapshot(
      prePromoFarePesewas: ride.prePromoFarePesewas,
      clientPayableEstimatePesewas: explicitClientPayable ??
          (hasCanonicalOfferContext && ride.hasEstimatedFareQuote
              ? ride.estimatedFarePesewas
              : null),
      promoDiscountPesewas: ride.promoDiscountPesewas,
      loyaltyDiscountPesewas: ride.loyaltyDiscountPesewas,
      platformDiscountPesewas: ride.platformDiscountPesewas,
      promoApplied: ride.promoApplied,
      legacyEstimatedFarePesewas:
          ride.hasEstimatedFareQuote ? ride.estimatedFarePesewas : null,
    );
  }

  factory IncomingRideFareSnapshot.fromJson(Map<String, dynamic> json) {
    int? integer(Object? value) {
      final parsed = switch (value) {
        final num value => value,
        final Object value => num.tryParse(value.toString()),
        null => null,
      };
      if (parsed == null || !parsed.isFinite || parsed < 0) return null;
      return parsed.toInt();
    }

    bool boolean(Object? value) => switch (value) {
          final bool value => value,
          final num value => value == 1,
          final Object value => value.toString().trim().toLowerCase() == 'true',
          null => false,
        };

    final prePromoFare = integer(json['prePromoFarePesewas']);
    final promoDiscount = integer(json['promoDiscountPesewas']);
    final loyaltyDiscount = integer(json['loyaltyDiscountPesewas']);
    final platformDiscount = integer(json['platformDiscountPesewas']);
    final legacyEstimatedFare = integer(
      json['estimatedFarePesewas'] ?? json['totalFare'],
    );
    final explicitClientPayable =
        integer(json['clientPayableEstimatePesewas']) ??
            integer(json['collectFromClientPesewas']);
    final hasCanonicalOfferContext = prePromoFare != null ||
        explicitClientPayable != null ||
        promoDiscount != null ||
        loyaltyDiscount != null ||
        platformDiscount != null;
    return IncomingRideFareSnapshot(
      prePromoFarePesewas: prePromoFare,
      clientPayableEstimatePesewas: explicitClientPayable ??
          (hasCanonicalOfferContext ? legacyEstimatedFare : null),
      promoDiscountPesewas: promoDiscount,
      loyaltyDiscountPesewas: loyaltyDiscount,
      platformDiscountPesewas: platformDiscount,
      promoApplied: boolean(json['promoApplied']) || (promoDiscount ?? 0) > 0,
      legacyEstimatedFarePesewas: legacyEstimatedFare,
    );
  }

  final int? prePromoFarePesewas;
  final int? clientPayableEstimatePesewas;
  final int? promoDiscountPesewas;
  final int? loyaltyDiscountPesewas;
  final int? platformDiscountPesewas;
  final bool promoApplied;
  final int? legacyEstimatedFarePesewas;

  /// Total discount shown to the provider. A complete quote is derived from
  /// the two displayed prices so the three rows always reconcile. Partial,
  /// transitional payloads may instead carry an authoritative platform total
  /// or the promo and loyalty components separately.
  int? get totalDiscountPesewas {
    final fullFare = prePromoFarePesewas;
    final clientPrice = clientPayableEstimatePesewas;
    if (fullFare != null && clientPrice != null && clientPrice <= fullFare) {
      return fullFare - clientPrice;
    }
    if (platformDiscountPesewas != null) return platformDiscountPesewas;
    if (promoDiscountPesewas != null || loyaltyDiscountPesewas != null) {
      return (promoDiscountPesewas ?? 0) + (loyaltyDiscountPesewas ?? 0);
    }
    return null;
  }

  bool get hasCurrentPricingContract {
    final fullFare = prePromoFarePesewas;
    final clientPrice = clientPayableEstimatePesewas;
    return fullFare != null && clientPrice != null && clientPrice <= fullFare;
  }
}

enum IncomingRidePrimaryAmountKind {
  fullTripFare,
  clientPrice,
  legacyEstimatedFare,
}

@immutable
class IncomingRideFareLine {
  const IncomingRideFareLine(this.label, this.amount);

  final String label;
  final String amount;
}

/// Display-ready copy shared by the Flutter request, FCM fallback, and native
/// Android bridge so each entry path uses the same financial semantics.
@immutable
class IncomingRideFareCopy {
  static const discountLabel = 'PROMO / DISCOUNT';

  const IncomingRideFareCopy({
    required this.primaryLabel,
    required this.primaryAmount,
    required this.primaryKind,
    required this.detailLines,
    required this.hasPrimaryAmount,
  });

  factory IncomingRideFareCopy.fromSnapshot(
    IncomingRideFareSnapshot fare, {
    String clientPriceLabel = 'CLIENT PRICE',
  }) {
    late final IncomingRidePrimaryAmountKind primaryKind;
    late final String primaryLabel;
    final int? primaryPesewas;
    if (fare.prePromoFarePesewas != null) {
      primaryKind = IncomingRidePrimaryAmountKind.fullTripFare;
      primaryLabel = 'EST. FULL FARE';
      primaryPesewas = fare.prePromoFarePesewas;
    } else if (fare.clientPayableEstimatePesewas != null) {
      primaryKind = IncomingRidePrimaryAmountKind.clientPrice;
      primaryLabel = 'CLIENT PRICE';
      primaryPesewas = fare.clientPayableEstimatePesewas;
    } else {
      primaryKind = IncomingRidePrimaryAmountKind.legacyEstimatedFare;
      primaryLabel = 'ESTIMATED FARE';
      primaryPesewas = fare.legacyEstimatedFarePesewas;
    }

    final lines = <IncomingRideFareLine>[];
    if (fare.hasCurrentPricingContract) {
      lines.add(
        IncomingRideFareLine(
          discountLabel,
          '- ${formatIncomingRidePesewas(fare.totalDiscountPesewas ?? 0)}',
        ),
      );
      lines.add(
        IncomingRideFareLine(
          clientPriceLabel,
          formatIncomingRidePesewas(fare.clientPayableEstimatePesewas!),
        ),
      );
    }

    return IncomingRideFareCopy(
      primaryLabel: primaryLabel,
      primaryAmount: primaryPesewas == null
          ? 'Fare available in MyShop'
          : formatIncomingRidePesewas(primaryPesewas),
      primaryKind: primaryKind,
      detailLines: List<IncomingRideFareLine>.unmodifiable(lines),
      hasPrimaryAmount: primaryPesewas != null,
    );
  }

  final String primaryLabel;
  final String primaryAmount;
  final IncomingRidePrimaryAmountKind primaryKind;
  final List<IncomingRideFareLine> detailLines;
  final bool hasPrimaryAmount;

  List<IncomingRideFareLine> get pricingLines => hasPrimaryAmount
      ? <IncomingRideFareLine>[
          IncomingRideFareLine(primaryLabel, primaryAmount),
          ...detailLines,
        ]
      : const <IncomingRideFareLine>[];

  String? get nativePricingSummary => detailLines.isEmpty
      ? null
      : detailLines.map((line) => '${line.label} ${line.amount}').join('\n');

  String get notificationPrimary => switch (primaryKind) {
        IncomingRidePrimaryAmountKind.fullTripFare =>
          'Est. full fare $primaryAmount',
        IncomingRidePrimaryAmountKind.clientPrice =>
          'Client price $primaryAmount',
        IncomingRidePrimaryAmountKind.legacyEstimatedFare =>
          'Estimated fare $primaryAmount',
      };
}

String formatIncomingRidePesewas(int pesewas) =>
    'GHS ${(pesewas / 100).toStringAsFixed(2)}';
