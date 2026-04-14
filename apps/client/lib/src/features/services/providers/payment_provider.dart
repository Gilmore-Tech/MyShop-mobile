import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Payment Method ────────────────────────────────────────────────────────────
// PRD 7.1 — supported client payment methods.
// Platform Payment covers all MoMo networks + card via Flutterwave.
// POST /v1/payments/initiate  (EDD § Payment Endpoints)

enum PaymentMethod { platformPayment, cash }

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.platformPayment => 'Platform Payment',
        PaymentMethod.cash            => 'Cash',
      };

  String get subtitle => switch (this) {
        PaymentMethod.platformPayment => 'Pay instantly from any wallet/MoMo',
        PaymentMethod.cash            => 'Pay with cash on completion',
      };

  IconData get icon => switch (this) {
        PaymentMethod.platformPayment => Icons.phone_android_rounded,
        PaymentMethod.cash            => Icons.payments_outlined,
      };
}

// ── Payment Summary ───────────────────────────────────────────────────────────
// Combined job + cost data for the payment review screen.
// Derived from GET /v1/jobs/:id after dual confirmation.
//
// Amount fields are in pesewas (integer) per EDD § Money Storage rules.
// totalPesewas is pre-calculated by the backend — includes any applicable VAT.

class PaymentSummary {
  // ── Job context ──
  final String jobId;

  /// Formatted service reference, e.g. "Service ID: #JOB-88219".
  final String serviceId;

  /// Short payment reference printed in the summary header, e.g. "JOB #GH-8821".
  final String paymentRef;

  final String jobTitle;
  final String paymentDescription;
  final String categoryName;
  final IconData categoryIcon;
  final String location;
  final String completionLabel; // e.g. "4hrs"

  // ── Artisan context ──
  final String artisanName;
  final String artisanFirstName;
  final Color artisanAvatarColor;

  // ── Cost breakdown (pesewas) ──
  final int serviceFeePesewas;
  final int materialsFeePesewas;

  /// Backend-calculated total (may include VAT / platform fee).
  final int totalPesewas;

  /// Wallet / cash balance available for the Cash payment option.
  final int walletBalancePesewas;

  const PaymentSummary({
    required this.jobId,
    required this.serviceId,
    required this.paymentRef,
    required this.jobTitle,
    required this.paymentDescription,
    required this.categoryName,
    required this.categoryIcon,
    required this.location,
    required this.completionLabel,
    required this.artisanName,
    required this.artisanFirstName,
    required this.artisanAvatarColor,
    required this.serviceFeePesewas,
    required this.materialsFeePesewas,
    required this.totalPesewas,
    required this.walletBalancePesewas,
  });

  String _fmt(int pesewas) => 'GHS ${(pesewas / 100).toStringAsFixed(2)}';

  String get serviceFeeDisplay   => _fmt(serviceFeePesewas);
  String get materialsFeeDisplay => _fmt(materialsFeePesewas);
  String get totalDisplay        => _fmt(totalPesewas);
  String get walletBalanceDisplay => _fmt(walletBalancePesewas);
}

// ── Payment Confirmation ──────────────────────────────────────────────────────
// Populated from the POST /v1/payments/initiate response on success.
// PRD 7.2: confirms funds are escrowed; released on dual confirmation.

class PaymentConfirmation {
  final String transactionRef;  // e.g. "#TXN-2024-8821"
  final String artisanName;
  final String jobTitle;
  final int amountPesewas;
  final PaymentMethod method;

  /// Human-readable timestamp, e.g. "24 Oct 2023, 02:30 PM".
  final String dateTimeLabel;

  const PaymentConfirmation({
    required this.transactionRef,
    required this.artisanName,
    required this.jobTitle,
    required this.amountPesewas,
    required this.method,
    required this.dateTimeLabel,
  });

  String get amountDisplay =>
      'GHS ${(amountPesewas / 100).toStringAsFixed(2)}';
}

// ── Payment State ─────────────────────────────────────────────────────────────

class PaymentState {
  final PaymentMethod selectedMethod;
  final bool isProcessing;
  final String? errorMessage;

  /// Non-null once payment is successfully escrowed.
  /// The screen listens for this to trigger the confirmation dialog.
  final PaymentConfirmation? confirmation;

  const PaymentState({
    this.selectedMethod = PaymentMethod.platformPayment,
    this.isProcessing = false,
    this.errorMessage,
    this.confirmation,
  });

  PaymentState copyWith({
    PaymentMethod? selectedMethod,
    bool? isProcessing,
    String? errorMessage,
    bool clearError = false,
    PaymentConfirmation? confirmation,
  }) =>
      PaymentState(
        selectedMethod: selectedMethod ?? this.selectedMethod,
        isProcessing: isProcessing ?? this.isProcessing,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        confirmation: confirmation ?? this.confirmation,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier() : super(const PaymentState());

  void selectMethod(PaymentMethod method) =>
      state = state.copyWith(selectedMethod: method);

  /// Initiates the escrow payment via Flutterwave.
  /// POST /v1/payments/initiate  (EDD § Payment Endpoints)
  /// PRD 7.2: funds held in micro-escrow, released on dual confirmation.
  /// Commission (20%) is deducted from the provider payout — not added here.
  Future<void> confirmPayment({
    required String jobId,
    required PaymentSummary summary,
  }) async {
    if (state.isProcessing) return;
    state = state.copyWith(isProcessing: true, clearError: true);
    // TODO: POST /v1/payments/initiate  { jobId, method: state.selectedMethod }
    await Future.delayed(const Duration(milliseconds: 900));
    state = state.copyWith(
      isProcessing: false,
      confirmation: PaymentConfirmation(
        transactionRef: '#TXN-2024-${summary.jobId.hashCode.abs() % 9000 + 1000}',
        artisanName: summary.artisanName,
        jobTitle: summary.jobTitle,
        amountPesewas: summary.totalPesewas,
        method: state.selectedMethod,
        dateTimeLabel: _formatNow(),
      ),
    );
  }

  static String _formatNow() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour   = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return '${now.day} ${months[now.month - 1]} ${now.year}, $hour:$minute $period';
  }
}

final paymentNotifierProvider =
    StateNotifierProvider.autoDispose<PaymentNotifier, PaymentState>(
  (_) => PaymentNotifier(),
);

// ── Data Provider ─────────────────────────────────────────────────────────────

final paymentSummaryProvider = AsyncNotifierProvider.autoDispose
    .family<_PaymentSummaryNotifier, PaymentSummary, String>(
  _PaymentSummaryNotifier.new,
);

class _PaymentSummaryNotifier
    extends AutoDisposeFamilyAsyncNotifier<PaymentSummary, String> {
  @override
  Future<PaymentSummary> build(String jobId) async {
    // TODO: GET /v1/jobs/:jobId — map confirmed job + bid cost to PaymentSummary
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockPayments[jobId] ?? _defaultMockPayment;
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

const _defaultMockPayment = PaymentSummary(
  jobId: 'JOB-1001',
  serviceId: 'Service ID: #JOB-88219',
  paymentRef: 'JOB #GH-8821',
  jobTitle: 'Emergency Electrical Repair',
  paymentDescription:
      'Circuit board inspection + 3 service hours. Funds will be '
      'held in escrow and released only after your confirmation.',
  categoryName: 'Electrical',
  categoryIcon: Icons.electrical_services_rounded,
  location: 'East Legon, Accra',
  completionLabel: '4hrs',
  artisanName: 'Kofi Mensah',
  artisanFirstName: 'Kofi',
  artisanAvatarColor: Color(0xFF37474F),
  serviceFeePesewas: 45000,   // GHS 450.00
  materialsFeePesewas: 20000, // GHS 200.00
  totalPesewas: 69825,        // GHS 698.25 (includes 4% transaction VAT)
  walletBalancePesewas: 124000, // GHS 1,240.00
);

const Map<String, PaymentSummary> _mockPayments = {};
