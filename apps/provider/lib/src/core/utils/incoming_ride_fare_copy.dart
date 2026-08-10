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
    this.estimatedProviderEarningsPesewas,
    this.prePromoFarePesewas,
    this.clientPayableEstimatePesewas,
    this.promoDiscountPesewas,
    this.loyaltyDiscountPesewas,
    this.platformDiscountPesewas,
    this.promoApplied = false,
    this.legacyEstimatedFarePesewas,
  });

  factory IncomingRideFareSnapshot.fromRide(Ride ride) {
    final hasCanonicalOfferContext =
        ride.estimatedProviderEarningsPesewas != null ||
            ride.prePromoFarePesewas != null ||
            ride.promoDiscountPesewas != null ||
            ride.loyaltyDiscountPesewas != null ||
            ride.platformDiscountPesewas != null;
    return IncomingRideFareSnapshot(
      estimatedProviderEarningsPesewas: ride.estimatedProviderEarningsPesewas,
      prePromoFarePesewas: ride.prePromoFarePesewas,
      clientPayableEstimatePesewas: ride.clientPayableEstimatePesewas ??
          ride.collectFromClientPesewas ??
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

    final estimatedProviderEarnings =
        integer(json['estimatedProviderEarningsPesewas']);
    final prePromoFare = integer(json['prePromoFarePesewas']);
    final promoDiscount = integer(json['promoDiscountPesewas']);
    final loyaltyDiscount = integer(json['loyaltyDiscountPesewas']);
    final platformDiscount = integer(json['platformDiscountPesewas']);
    final legacyEstimatedFare =
        integer(json['estimatedFarePesewas'] ?? json['totalFare']);
    final hasCanonicalOfferContext = estimatedProviderEarnings != null ||
        prePromoFare != null ||
        promoDiscount != null ||
        loyaltyDiscount != null ||
        platformDiscount != null;
    return IncomingRideFareSnapshot(
      estimatedProviderEarningsPesewas: estimatedProviderEarnings,
      prePromoFarePesewas: prePromoFare,
      clientPayableEstimatePesewas: integer(
            json['clientPayableEstimatePesewas'] ??
                json['collectFromClientPesewas'],
          ) ??
          (hasCanonicalOfferContext ? legacyEstimatedFare : null),
      promoDiscountPesewas: promoDiscount,
      loyaltyDiscountPesewas: loyaltyDiscount,
      platformDiscountPesewas: platformDiscount,
      promoApplied: boolean(json['promoApplied']) || (promoDiscount ?? 0) > 0,
      legacyEstimatedFarePesewas: legacyEstimatedFare,
    );
  }

  final int? estimatedProviderEarningsPesewas;
  final int? prePromoFarePesewas;
  final int? clientPayableEstimatePesewas;
  final int? promoDiscountPesewas;
  final int? loyaltyDiscountPesewas;
  final int? platformDiscountPesewas;
  final bool promoApplied;
  final int? legacyEstimatedFarePesewas;

  /// Total MyShop-funded value. Prefer the backend's reconciled total, then
  /// add the two explicit components when talking to a transitional server.
  int? get myShopCoveredPesewas {
    if (platformDiscountPesewas != null) return platformDiscountPesewas;
    if (promoDiscountPesewas == null && loyaltyDiscountPesewas == null) {
      return null;
    }
    return (promoDiscountPesewas ?? 0) + (loyaltyDiscountPesewas ?? 0);
  }

  bool get hasCurrentDiscount =>
      promoApplied || (myShopCoveredPesewas ?? 0) > 0;
}

enum IncomingRidePrimaryAmountKind {
  estimatedEarnings,
  fullTripFare,
  riderPays,
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
  const IncomingRideFareCopy({
    required this.primaryLabel,
    required this.primaryAmount,
    required this.primaryKind,
    required this.detailLines,
    required this.hasPrimaryAmount,
  });

  factory IncomingRideFareCopy.fromSnapshot(
    IncomingRideFareSnapshot fare, {
    String? paymentMethod,
  }) {
    late final IncomingRidePrimaryAmountKind primaryKind;
    late final String primaryLabel;
    final int? primaryPesewas;
    if (fare.estimatedProviderEarningsPesewas != null) {
      primaryKind = IncomingRidePrimaryAmountKind.estimatedEarnings;
      primaryLabel = 'ESTIMATED EARNINGS';
      primaryPesewas = fare.estimatedProviderEarningsPesewas;
    } else if (fare.prePromoFarePesewas != null) {
      primaryKind = IncomingRidePrimaryAmountKind.fullTripFare;
      primaryLabel = 'EST. FULL FARE';
      primaryPesewas = fare.prePromoFarePesewas;
    } else if (fare.clientPayableEstimatePesewas != null) {
      primaryKind = IncomingRidePrimaryAmountKind.riderPays;
      primaryLabel = _riderQuoteLabel(paymentMethod);
      primaryPesewas = fare.clientPayableEstimatePesewas;
    } else {
      primaryKind = IncomingRidePrimaryAmountKind.legacyEstimatedFare;
      primaryLabel = 'ESTIMATED FARE';
      primaryPesewas = fare.legacyEstimatedFarePesewas;
    }

    final lines = <IncomingRideFareLine>[];
    final tripFare = fare.prePromoFarePesewas;
    final riderPays = fare.clientPayableEstimatePesewas;
    final covered = fare.myShopCoveredPesewas;
    final discounted = fare.hasCurrentDiscount;

    if (!discounted &&
        tripFare != null &&
        riderPays != null &&
        tripFare == riderPays &&
        primaryKind != IncomingRidePrimaryAmountKind.fullTripFare &&
        primaryKind != IncomingRidePrimaryAmountKind.riderPays) {
      lines.add(
        IncomingRideFareLine(
          'EST. FULL FARE · ${_riderQuoteLabel(paymentMethod)}',
          formatIncomingRidePesewas(tripFare),
        ),
      );
    } else {
      if (tripFare != null &&
          primaryKind != IncomingRidePrimaryAmountKind.fullTripFare) {
        lines.add(
          IncomingRideFareLine(
            'EST. FULL FARE',
            formatIncomingRidePesewas(tripFare),
          ),
        );
      }
      if (riderPays != null &&
          primaryKind != IncomingRidePrimaryAmountKind.riderPays) {
        lines.add(
          IncomingRideFareLine(
            _riderQuoteLabel(paymentMethod),
            formatIncomingRidePesewas(riderPays),
          ),
        );
      }
    }
    if (covered != null && covered > 0) {
      lines.add(
        IncomingRideFareLine(
          'MYSHOP COVERS',
          formatIncomingRidePesewas(covered),
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

  String? get nativePricingSummary => detailLines.isEmpty
      ? null
      : detailLines
          .map((line) => '${_sentenceCase(line.label)} ${line.amount}')
          .join(' · ');

  String get notificationPrimary => switch (primaryKind) {
        IncomingRidePrimaryAmountKind.estimatedEarnings =>
          'Est. earnings $primaryAmount',
        IncomingRidePrimaryAmountKind.fullTripFare =>
          'Est. full fare $primaryAmount',
        IncomingRidePrimaryAmountKind.riderPays =>
          '${_sentenceCase(primaryLabel)} $primaryAmount',
        IncomingRidePrimaryAmountKind.legacyEstimatedFare =>
          'Estimated fare $primaryAmount',
      };
}

String formatIncomingRidePesewas(int pesewas) =>
    'GHS ${(pesewas / 100).toStringAsFixed(2)}';

String _riderQuoteLabel(String? paymentMethod) {
  final method = paymentMethod?.trim().toLowerCase();
  if (method == 'cash') return 'RIDER QUOTE · CASH';
  if (method != null && method.isNotEmpty) return 'RIDER QUOTE · IN APP';
  return 'RIDER QUOTE';
}

String _sentenceCase(String value) {
  final lower = value.toLowerCase();
  return lower.isEmpty
      ? lower
      : '${lower[0].toUpperCase()}${lower.substring(1)}';
}
