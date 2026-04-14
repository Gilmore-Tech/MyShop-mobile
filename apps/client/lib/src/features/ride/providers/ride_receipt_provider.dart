import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Payment Method ─────────────────────────────────────────────────────────────
// Defined here and re-exported so service_receipt_provider can share the type.

enum PaymentMethodType { mtn, vodafone, airtelTigo, visa, mastercard, cash }

// ── Ride Receipt Data ──────────────────────────────────────────────────────────
// Populated from GET /v1/rides/:id once status == completed (EDD § Ride Module).
// All monetary values in pesewas (int).  100 pesewas = GH¢ 1.

class RideReceiptData {
  final String            rideId;           // "RID-99283-GH"
  final String            driverName;       // "Kojo Mensah"
  final String            vehicleDisplay;   // "Toyota Corolla · GW 1234-21"
  final double            driverRating;     // 4.9
  final String            pickupAddress;
  final String            dropoffAddress;

  // Fare components (pesewas)
  final int               baseFarePesewas;
  final double            distanceKm;
  final int               distanceFarePesewas;
  final int               bookingFeePesewas;
  final int               taxesPesewas;
  final int               totalPaidPesewas;

  final String            dateTimeLabel;       // "24 May 2024, 14:32"
  final String            paymentMethodLabel;  // "MTN Mobile Money"
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
    required this.totalPaidPesewas,
    required this.dateTimeLabel,
    required this.paymentMethodLabel,
    required this.paymentMethodType,
  });

  static String _fmt(int p) => 'GH¢ ${(p / 100.0).toStringAsFixed(2)}';

  String get baseFareDisplay     => _fmt(baseFarePesewas);
  String get distanceFareDisplay => _fmt(distanceFarePesewas);
  String get bookingFeeDisplay   => _fmt(bookingFeePesewas);
  String get taxesDisplay        => _fmt(taxesPesewas);
  String get totalPaidDisplay    => _fmt(totalPaidPesewas);
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
    // TODO: GET /v1/rides/:rideId — map API response fields to RideReceiptData
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockReceipts[rideId] ?? _defaultMock;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }
}

// ── Mock data ──────────────────────────────────────────────────────────────────

const _defaultMock = RideReceiptData(
  rideId:              'RID-99283-GH',
  driverName:          'Kojo Mensah',
  vehicleDisplay:      'Toyota Corolla · GW 1234-21',
  driverRating:        4.9,
  pickupAddress:       'Kotoka International Airport (ACC)',
  dropoffAddress:      'Oxford Street, Osu, Accra',
  baseFarePesewas:     1000,  // GH¢ 10.00
  distanceKm:          12.4,
  distanceFarePesewas: 2850,  // GH¢ 28.50
  bookingFeePesewas:   500,   // GH¢  5.00
  taxesPesewas:        200,   // GH¢  2.00
  totalPaidPesewas:    4550,  // GH¢ 45.50
  dateTimeLabel:       '24 May 2024, 14:32',
  paymentMethodLabel:  'MTN Mobile Money',
  paymentMethodType:   PaymentMethodType.mtn,
);

/// Keyed mock receipts — populate when wiring to real API.
const _mockReceipts = <String, RideReceiptData>{};
