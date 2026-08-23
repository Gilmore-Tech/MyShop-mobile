import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' show RideToll;

import '../../../core/di/providers.dart';
import 'ride_provider.dart' show RideFareFields;

// ── Payment Method ─────────────────────────────────────────────────────────────
// Defined here and re-exported so service_receipt_provider can share the type.

enum PaymentMethodType { mtn, vodafone, airtelTigo, visa, mastercard, cash }

// ── Ride Receipt Data ──────────────────────────────────────────────────────────
// Populated from GET /v1/rides/:id once status == completed (EDD § Ride Module).
// All monetary values in pesewas (int).  100 pesewas = GH¢ 1.

class RideReceiptData {
  final String rideId; // "RID-99283-GH"
  final String driverName; // "Kojo Mensah"
  final String vehicleDisplay; // "Toyota Corolla · GW 1234-21"
  /// Average revealed rating (0–5). Null when the driver has no
  /// revealed ratings yet — display widgets render "New" rather than a
  /// fake number. The earlier code defaulted to 0.0 which printed as
  /// "0.0★".
  final double? driverRating;
  final String pickupAddress;
  final String dropoffAddress;

  // Fare components (pesewas)
  final int baseFarePesewas;
  final double distanceKm;
  final int distanceFarePesewas;
  final int bookingFeePesewas;
  final int taxesPesewas;
  final RideToll? toll;
  final int promoDiscountPesewas;
  final int loyaltyDiscountPesewas;
  final int totalPaidPesewas;

  final String dateTimeLabel; // "24 May 2024, 14:32"
  final String paymentMethodLabel; // "MTN Mobile Money"
  final PaymentMethodType paymentMethodType;

  const RideReceiptData({
    required this.rideId,
    required this.driverName,
    required this.vehicleDisplay,
    required this.driverRating,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.baseFarePesewas,
    required this.distanceKm,
    required this.distanceFarePesewas,
    required this.bookingFeePesewas,
    required this.taxesPesewas,
    this.toll,
    required this.promoDiscountPesewas,
    required this.loyaltyDiscountPesewas,
    required this.totalPaidPesewas,
    required this.dateTimeLabel,
    required this.paymentMethodLabel,
    required this.paymentMethodType,
  });

  static String _fmt(int p) => 'GH¢ ${(p / 100.0).toStringAsFixed(2)}';

  String get baseFareDisplay => _fmt(baseFarePesewas);
  String get distanceFareDisplay => _fmt(distanceFarePesewas);
  String get bookingFeeDisplay => _fmt(bookingFeePesewas);
  String get taxesDisplay => _fmt(taxesPesewas);
  String get tollDisplay => _fmt(toll?.amountPesewas ?? 0);
  String get promoDiscountDisplay => '- ${_fmt(promoDiscountPesewas)}';
  String get loyaltyDiscountDisplay => '- ${_fmt(loyaltyDiscountPesewas)}';
  String get totalPaidDisplay => _fmt(totalPaidPesewas);
}

// ── Provider ───────────────────────────────────────────────────────────────────
// Family keyed by rideId so the activity list can open any historical receipt.

final rideReceiptByIdProvider = AsyncNotifierProvider.autoDispose
    .family<_RideReceiptNotifier, RideReceiptData, String>(
  _RideReceiptNotifier.new,
);

class _RideReceiptNotifier
    extends AutoDisposeFamilyAsyncNotifier<RideReceiptData, String> {
  @override
  Future<RideReceiptData> build(String rideId) async {
    final rideService = ref.watch(rideServiceProvider);

    try {
      final ride = await rideService.getRide(rideId);
      final driver =
          ride['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final fare = RideFareFields.fromSnapshot(ride);

      // Parse payment method type from API label
      final paymentLabel = ride['paymentMethod'] as String? ?? 'Cash';
      final pmType = _parsePaymentMethodType(paymentLabel);

      return RideReceiptData(
        rideId: ride['id'] as String? ?? rideId,
        driverName: driver['name'] as String? ?? 'Driver',
        vehicleDisplay:
            '${driver['vehicleShortName'] ?? driver['vehicle'] ?? ''}'
            ' · ${driver['plateNumber'] ?? ''}',
        driverRating: (driver['rating'] as num?)?.toDouble(),
        pickupAddress: ride['pickupAddress'] as String? ?? '',
        // Backend's RideSnapshot serves the field as `dropoffAddress`; the
        // older `destinationAddress` alias never made it into the canonical
        // payload, so reading it returned null and the receipt was blank.
        dropoffAddress:
            (ride['dropoffAddress'] ?? ride['destinationAddress']) as String? ??
                '',
        baseFarePesewas: fare.baseFarePesewas,
        distanceKm: fare.distanceKm,
        distanceFarePesewas: fare.distanceFarePesewas,
        bookingFeePesewas: fare.bookingFeePesewas,
        taxesPesewas: fare.taxesPesewas,
        toll: fare.toll,
        promoDiscountPesewas: fare.promoDiscountPesewas,
        loyaltyDiscountPesewas: fare.loyaltyDiscountPesewas,
        totalPaidPesewas: fare.totalFarePesewas,
        dateTimeLabel: ride['completedAt'] as String? ?? '',
        paymentMethodLabel: paymentLabel,
        paymentMethodType: pmType,
      );
    } on ApiException catch (e) {
      developer.log(
        'getRide receipt failed (${e.statusCode}): ${e.message}',
        name: 'RideReceiptProvider',
      );
      rethrow;
    } catch (e) {
      developer.log('getRide receipt error: $e', name: 'RideReceiptProvider');
      rethrow;
    }
  }

  static PaymentMethodType _parsePaymentMethodType(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('mtn')) return PaymentMethodType.mtn;
    if (lower.contains('vodafone')) return PaymentMethodType.vodafone;
    if (lower.contains('airtel') || lower.contains('tigo')) {
      return PaymentMethodType.airtelTigo;
    }
    if (lower.contains('visa')) return PaymentMethodType.visa;
    if (lower.contains('master')) return PaymentMethodType.mastercard;
    return PaymentMethodType.cash;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }
}
