import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ride/providers/ride_receipt_provider.dart' show PaymentMethodType;

// ── Service Receipt Data ───────────────────────────────────────────────────────
// Populated from GET /v1/jobs/:id once status == completed (EDD § Job Module).
// All monetary values in pesewas (int).  100 pesewas = GH¢ 1.

class ServiceReceiptData {
  final String            jobId;              // "JOB-44102-GH"
  final String            artisanName;        // "Ama Serwaa"
  final String            artisanSpecialty;   // "Certified Electrician"
  final double            artisanRating;      // 4.8
  final String            serviceLocation;    // "Plot 14, East Legon Residential Area"
  final String            workDurationLabel;  // "2h 15m"

  // Cost breakdown (pesewas)
  final int               serviceCallFeePesewas;
  final int               laborPesewas;
  final String            laborHoursLabel;    // "2 Hours" — shown as "Labor (2 Hours)"
  final int               materialsPesewas;
  final int               totalPaidPesewas;

  final String            dateTimeLabel;       // "23 May 2024, 10:15"
  final String            paymentMethodLabel;  // "Visa ****4242"
  final PaymentMethodType paymentMethodType;

  const ServiceReceiptData({
    required this.jobId,
    required this.artisanName,
    required this.artisanSpecialty,
    required this.artisanRating,
    required this.serviceLocation,
    required this.workDurationLabel,
    required this.serviceCallFeePesewas,
    required this.laborPesewas,
    required this.laborHoursLabel,
    required this.materialsPesewas,
    required this.totalPaidPesewas,
    required this.dateTimeLabel,
    required this.paymentMethodLabel,
    required this.paymentMethodType,
  });

  static String _fmt(int p) => 'GH¢ ${(p / 100.0).toStringAsFixed(2)}';

  String get serviceCallFeeDisplay => _fmt(serviceCallFeePesewas);
  String get laborDisplay          => _fmt(laborPesewas);
  String get materialsDisplay      => _fmt(materialsPesewas);
  String get totalPaidDisplay      => _fmt(totalPaidPesewas);
}

// ── Provider ───────────────────────────────────────────────────────────────────
// Family keyed by jobId so the activity list can open any historical receipt.

final serviceReceiptByIdProvider = AsyncNotifierProvider.autoDispose
    .family<_ServiceReceiptNotifier, ServiceReceiptData, String>(
  _ServiceReceiptNotifier.new,
);

class _ServiceReceiptNotifier
    extends AutoDisposeFamilyAsyncNotifier<ServiceReceiptData, String> {
  @override
  Future<ServiceReceiptData> build(String jobId) async {
    // TODO: GET /v1/jobs/:jobId — map API response fields to ServiceReceiptData
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockReceipts[jobId] ?? _defaultMock;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }
}

// ── Mock data ──────────────────────────────────────────────────────────────────

const _defaultMock = ServiceReceiptData(
  jobId:                  'JOB-44102-GH',
  artisanName:            'Ama Serwaa',
  artisanSpecialty:       'Certified Electrician',
  artisanRating:          4.8,
  serviceLocation:        'Plot 14, East Legon Residential Area',
  workDurationLabel:      '2h 15m',
  serviceCallFeePesewas:  3000,   // GH¢ 30.00
  laborPesewas:           8000,   // GH¢ 80.00
  laborHoursLabel:        '2 Hours',
  materialsPesewas:       1000,   // GH¢ 10.00
  totalPaidPesewas:       12000,  // GH¢ 120.00
  dateTimeLabel:          '23 May 2024, 10:15',
  paymentMethodLabel:     'Visa ****4242',
  paymentMethodType:      PaymentMethodType.visa,
);

/// Keyed mock receipts — populate when wiring to real API.
const _mockReceipts = <String, ServiceReceiptData>{};
