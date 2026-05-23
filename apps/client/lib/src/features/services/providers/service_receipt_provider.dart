import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';
import '../../ride/providers/ride_receipt_provider.dart' show PaymentMethodType;

// ── Service Receipt Data ───────────────────────────────────────────────────────
// Populated from GET /v1/jobs/:id once status == completed (EDD § Job Module).
// All monetary values in pesewas (int).  100 pesewas = GH¢ 1.

class ServiceReceiptData {
  final String jobId; // "JOB-44102-GH"

  /// Backend job status — used to gate the Rate CTA so the client only
  /// sees it once the booking is truly settled (not at
  /// `artisan_marked_complete`, where the rating endpoint will 410).
  final String status; // "completed", "artisan_marked_complete", ...

  final String artisanName; // "Ama Serwaa"
  final String artisanSpecialty; // "Certified Electrician"
  final double artisanRating; // 4.8
  final String serviceLocation; // "Plot 14, East Legon Residential Area"
  final String workDurationLabel; // "2h 15m"

  // Cost breakdown (pesewas)
  final int serviceCallFeePesewas;
  final int laborPesewas;
  final String laborHoursLabel; // "2 Hours" — shown as "Labor (2 Hours)"
  final int materialsPesewas;
  final int totalPaidPesewas;

  final String dateTimeLabel; // "23 May 2024, 10:15"
  final String paymentMethodLabel; // "Visa ****4242"
  final PaymentMethodType paymentMethodType;

  const ServiceReceiptData({
    required this.jobId,
    required this.status,
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

  /// True once the backend has flipped the job to `completed` — i.e.
  /// payment has settled (Paystack webhook OR artisan-confirms-cash).
  /// The rating endpoint only accepts submissions in this state.
  bool get isCompleted => status == 'completed';

  static String _fmt(int p) => 'GH¢ ${(p / 100.0).toStringAsFixed(2)}';

  String get serviceCallFeeDisplay => _fmt(serviceCallFeePesewas);
  String get laborDisplay => _fmt(laborPesewas);
  String get materialsDisplay => _fmt(materialsPesewas);
  String get totalPaidDisplay => _fmt(totalPaidPesewas);
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
    final jobService = ref.watch(jobServiceProvider);
    final data = await jobService.getJob(jobId);
    return _parseReceipt(data);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }

  /// Parse API response into [ServiceReceiptData].
  static ServiceReceiptData _parseReceipt(Map<String, dynamic> data) {
    final artisanData = data['provider'] as Map<String, dynamic>? ?? {};
    final costBreakdown = data['costBreakdown'] as Map<String, dynamic>? ?? {};
    final paymentData = data['payment'] as Map<String, dynamic>? ?? {};

    final artisanName =
        '${artisanData['firstName'] ?? ''} ${artisanData['lastName'] ?? ''}'
            .trim();
    final serviceCallFeePesewas =
        (costBreakdown['serviceCallFeePesewas'] as num?)?.toInt() ?? 0;
    final laborPesewas = (costBreakdown['laborPesewas'] as num?)?.toInt() ?? 0;
    final materialsPesewas =
        (costBreakdown['materialsPesewas'] as num?)?.toInt() ?? 0;
    final totalPesewas = (data['totalPesewas'] as num?)?.toInt() ??
        serviceCallFeePesewas + laborPesewas + materialsPesewas;

    final paymentMethodStr = paymentData['method'] as String? ?? '';
    final paymentMethodType = switch (paymentMethodStr) {
      'mobile_money' || 'mtn' => PaymentMethodType.mtn,
      'vodafone' => PaymentMethodType.vodafone,
      'airtel_tigo' => PaymentMethodType.airtelTigo,
      'visa' => PaymentMethodType.visa,
      'mastercard' => PaymentMethodType.mastercard,
      'cash' => PaymentMethodType.cash,
      _ => PaymentMethodType.mtn,
    };

    return ServiceReceiptData(
      jobId: data['id'] as String? ?? '',
      status: data['status'] as String? ?? '',
      artisanName: artisanName.isNotEmpty ? artisanName : 'Artisan',
      artisanSpecialty: artisanData['specialty'] as String? ?? '',
      artisanRating: ((artisanData['averageRating'] ?? artisanData['rating'])
                  as num?)
              ?.toDouble() ??
          0.0,
      serviceLocation: data['locationAddress'] as String? ?? '',
      workDurationLabel: data['workDurationLabel'] as String? ?? '—',
      serviceCallFeePesewas: serviceCallFeePesewas,
      laborPesewas: laborPesewas,
      laborHoursLabel: costBreakdown['laborHoursLabel'] as String? ?? '',
      materialsPesewas: materialsPesewas,
      totalPaidPesewas: totalPesewas,
      dateTimeLabel: _formatReceiptDate(data['completedAt'] as String?),
      paymentMethodLabel: paymentData['label'] as String? ?? '',
      paymentMethodType: paymentMethodType,
    );
  }
}

/// Format the completedAt ISO timestamp as a receipt-friendly label
/// in the user's local time zone. Renders like "22 May 2026 · 10:14 PM".
/// Returns an empty string for missing/invalid input so the receipt UI
/// can fall back to its placeholder rather than showing "1970-01-01".
String _formatReceiptDate(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return '';
  return DateFormat('d MMM yyyy · h:mm a').format(dt.toLocal());
}

