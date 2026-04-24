import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../../../core/di/providers.dart';

/// Recursively scans a decoded payments-initiate response for a Paystack
/// checkout URL. The exact response shape varies depending on whether the
/// backend returns the raw Paystack payload, wraps it in its own envelope,
/// or just surfaces the fields under different names — so rather than
/// hardcoding a path we walk the tree.
String? _findCheckoutUrl(Object? node) {
  if (node is String) {
    if (node.startsWith('http') &&
        (node.contains('paystack') || node.contains('checkout'))) {
      return node;
    }
    return null;
  }
  if (node is Map) {
    // Prefer well-known key names first — a plain key lookup beats a scan
    // when the field is exactly where we expect it.
    for (final key in const [
      'authorizationUrl',
      'authorization_url',
      'checkoutUrl',
      'checkout_url',
      'redirectUrl',
      'redirect_url',
      'paymentUrl',
      'payment_url',
    ]) {
      final v = node[key];
      if (v is String && v.startsWith('http')) return v;
    }
    for (final v in node.values) {
      final hit = _findCheckoutUrl(v);
      if (hit != null) return hit;
    }
  }
  if (node is List) {
    for (final v in node) {
      final hit = _findCheckoutUrl(v);
      if (hit != null) return hit;
    }
  }
  return null;
}

/// Pulls the Paystack reference / payment id out of the response, again
/// tolerating shape drift. Used to display a short ref in the success card.
String? _findPaymentRef(Object? node) {
  if (node is Map) {
    for (final key in const [
      'paymentId',
      'payment_id',
      'transactionRef',
      'transaction_ref',
      'reference',
      'id',
    ]) {
      final v = node[key];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final v in node.values) {
      final hit = _findPaymentRef(v);
      if (hit != null) return hit;
    }
  }
  if (node is List) {
    for (final v in node) {
      final hit = _findPaymentRef(v);
      if (hit != null) return hit;
    }
  }
  return null;
}

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

/// Where the charge is in its lifecycle.
///
///   idle         → nothing in flight, awaiting user action
///   processing   → local call to /payments/initiate is in flight
///   awaitingSettlement → Paystack charge queued, job is `pending_payment`.
///                        The webhook will flip the job to `completed` (or
///                        back to `artisan_marked_complete` on failure).
///   settled      → job status has landed as `completed`; PATCH /confirm ran
///                  (idempotent) and the success dialog is showing.
///   failed       → charge failed. Job reverted to `artisan_marked_complete`
///                  so the client can retry the payment.
enum PaymentPhase { idle, processing, awaitingSettlement, settled, failed }

class PaymentState {
  final PaymentMethod selectedMethod;
  final PaymentPhase phase;
  final String? errorMessage;

  /// Non-null once the charge has settled AND PATCH /confirm has succeeded.
  /// The screen listens for this to trigger the confirmation dialog.
  final PaymentConfirmation? confirmation;

  /// Paystack checkout URL returned by /payments/initiate when the charge
  /// needs a browser redirect (card / first-time MoMo). Null when the charge
  /// can settle without a redirect (MoMo push, saved card).
  final String? authorizationUrl;

  /// Paystack reference for this charge — used to poll status if the socket
  /// event doesn't land within the timeout.
  final String? paymentId;

  const PaymentState({
    this.selectedMethod = PaymentMethod.platformPayment,
    this.phase = PaymentPhase.idle,
    this.errorMessage,
    this.confirmation,
    this.authorizationUrl,
    this.paymentId,
  });

  bool get isProcessing => phase == PaymentPhase.processing;
  bool get isAwaitingSettlement => phase == PaymentPhase.awaitingSettlement;

  PaymentState copyWith({
    PaymentMethod? selectedMethod,
    PaymentPhase? phase,
    String? errorMessage,
    bool clearError = false,
    PaymentConfirmation? confirmation,
    String? authorizationUrl,
    bool clearAuthorizationUrl = false,
    String? paymentId,
  }) =>
      PaymentState(
        selectedMethod: selectedMethod ?? this.selectedMethod,
        phase: phase ?? this.phase,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        confirmation: confirmation ?? this.confirmation,
        authorizationUrl: clearAuthorizationUrl
            ? null
            : (authorizationUrl ?? this.authorizationUrl),
        paymentId: paymentId ?? this.paymentId,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier(this._paymentService, this._jobService)
      : super(const PaymentState());

  final PaymentService _paymentService;
  final JobService _jobService;

  void selectMethod(PaymentMethod method) =>
      state = state.copyWith(selectedMethod: method);

  /// Initiates the Paystack escrow charge.
  ///   POST /v1/payments/initiate  (bookingType: 'artisan_job')
  ///
  /// Backend flips the job to `pending_payment`, queues the charge, and
  /// returns Paystack's `authorization_url` (hosted checkout). The caller
  /// launches that URL externally; the user completes the payment on
  /// Paystack, and the `charge.success` webhook fires `job:status:changed`
  /// with `completed` — which drives [confirmCompletion] on the settling
  /// side of the screen.
  Future<void> confirmPayment({
    required String jobId,
    required PaymentSummary summary,
  }) async {
    if (state.isProcessing) return;
    state = state.copyWith(phase: PaymentPhase.processing, clearError: true);
    try {
      final methodStr = state.selectedMethod == PaymentMethod.platformPayment
          ? 'mobile_money'
          : 'cash';
      final result = await _paymentService.initiatePayment(
        bookingType: 'artisan_job',
        bookingId: jobId,
        paymentMethod: methodStr,
      );
      // Log the raw response so it's visible in the dev console. Paystack
      // responses differ across channels (MoMo / card / saved auth) and
      // across backend wrappers — keep this around until the flow is
      // battle-tested on prod data.
      developer.log(
        'initiatePayment response: $result',
        name: 'Payment',
      );
      final authUrl = _findCheckoutUrl(result);
      final paymentId = _findPaymentRef(result);

      // If the backend queued the charge but gave us no URL, we can't
      // open anything — flag it so the UI prompts the user correctly
      // (e.g. "Check your phone to approve" for a MoMo push flow) rather
      // than spinning forever.
      if (authUrl == null) {
        developer.log(
          'initiatePayment returned no checkout URL — '
          'awaiting webhook settlement instead.',
          name: 'Payment',
          level: 800,
        );
      }

      state = state.copyWith(
        phase: PaymentPhase.awaitingSettlement,
        authorizationUrl: authUrl,
        paymentId: paymentId,
      );
    } on ApiException catch (e) {
      developer.log(
        'initiatePayment failed: ${e.errorCode} — ${e.message}',
        name: 'Payment',
        level: 1000,
      );
      state = state.copyWith(
        phase: PaymentPhase.idle,
        errorMessage: _friendlyInitiateError(e),
      );
    } catch (e, st) {
      developer.log(
        'initiatePayment crashed: $e\n$st',
        name: 'Payment',
        level: 1200,
      );
      state = state.copyWith(
        phase: PaymentPhase.idle,
        errorMessage: 'Could not start payment. Please try again.',
      );
    }
  }

  String _friendlyInitiateError(ApiException e) {
    switch (e.errorCode) {
      case 'JOB_NOT_AWAITING_PAYMENT':
        return "This job isn't ready for payment yet. Ask the artisan to "
            'mark the work complete and try again.';
      case 'PAYMENT_ALREADY_SETTLED':
        return 'This job has already been paid for.';
      default:
        return e.message;
    }
  }

  /// Called by the payment screen once the job has landed as `completed`
  /// (socket event or poll). Runs PATCH /jobs/:id/confirm — idempotent,
  /// safe even if the webhook already finalised the job.
  Future<void> confirmCompletion({
    required String jobId,
    required PaymentSummary summary,
  }) async {
    if (state.phase == PaymentPhase.settled) return;
    try {
      await _jobService.confirmJobCompletion(jobId);
    } on ApiException catch (e) {
      // PAYMENT_NOT_SETTLED means the socket event was a false start — keep
      // waiting. Any other code is a real error worth surfacing.
      if (e.errorCode == 'PAYMENT_NOT_SETTLED') return;
      state = state.copyWith(errorMessage: e.message);
      return;
    } catch (_) {
      // Treat unexpected errors as non-fatal — the socket will drive us
      // back through here on the next status tick.
      return;
    }
    state = state.copyWith(
      phase: PaymentPhase.settled,
      confirmation: PaymentConfirmation(
        transactionRef: state.paymentId ??
            '#TXN-${summary.jobId.hashCode.abs() % 9000 + 1000}',
        artisanName: summary.artisanName,
        jobTitle: summary.jobTitle,
        amountPesewas: summary.totalPesewas,
        method: state.selectedMethod,
        dateTimeLabel: _formatNow(),
      ),
    );
  }

  /// Called when the socket reports the job bounced back to
  /// `artisan_marked_complete` — Paystack charge failed. The user can tap
  /// "Retry payment" which resets state and re-enters the flow.
  void markPaymentFailed(String message) {
    state = state.copyWith(
      phase: PaymentPhase.failed,
      errorMessage: message,
      clearAuthorizationUrl: true,
    );
  }

  /// Clears the auth URL once the screen has launched it, so the listener
  /// fires again if the user retries and a new URL comes back.
  void consumeAuthorizationUrl() {
    state = state.copyWith(clearAuthorizationUrl: true);
  }

  void resetForRetry() {
    state = state.copyWith(
      phase: PaymentPhase.idle,
      clearError: true,
      clearAuthorizationUrl: true,
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
  (ref) => PaymentNotifier(
    ref.watch(paymentServiceProvider),
    ref.watch(jobServiceProvider),
  ),
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
    try {
      final jobService = ref.watch(jobServiceProvider);
      final data = await jobService.getJob(jobId);
      return _parsePaymentSummary(data);
    } catch (_) {
      // Fallback to mock during development / if endpoint not ready
      return _mockPayments[jobId] ?? _defaultMockPayment;
    }
  }

  /// Parse API response into [PaymentSummary].
  PaymentSummary _parsePaymentSummary(Map<String, dynamic> data) {
    final bidData = data['selectedBid'] as Map<String, dynamic>? ?? {};
    final costBreakdown = data['costBreakdown'] as Map<String, dynamic>? ?? {};
    final artisanData = data['provider'] as Map<String, dynamic>? ?? {};
    final categoryData = data['category'] as Map<String, dynamic>? ?? {};

    final artisanName = '${artisanData['firstName'] ?? ''} ${artisanData['lastName'] ?? ''}'.trim();
    final serviceFeePesewas = (costBreakdown['laborPesewas'] as num?)?.toInt()
        ?? (bidData['amountPesewas'] as num?)?.toInt()
        ?? 0;
    final materialsFeePesewas = (costBreakdown['materialsPesewas'] as num?)?.toInt() ?? 0;
    final totalPesewas = (data['totalPesewas'] as num?)?.toInt()
        ?? serviceFeePesewas + materialsFeePesewas;

    return PaymentSummary(
      jobId: data['id'] as String? ?? '',
      serviceId: 'Service ID: #${data['id'] ?? ''}',
      paymentRef: 'JOB #${data['id'] ?? ''}',
      jobTitle: data['description'] as String? ?? '',
      paymentDescription: bidData['message'] as String? ??
          'Funds will be held in escrow and released only after your confirmation.',
      categoryName: categoryData['name'] as String? ?? '',
      categoryIcon: Icons.build_rounded,
      location: data['locationAddress'] as String? ?? '',
      completionLabel: data['estimatedDuration'] as String? ?? '—',
      artisanName: artisanName.isNotEmpty ? artisanName : 'Artisan',
      artisanFirstName: artisanData['firstName'] as String? ?? 'Artisan',
      artisanAvatarColor: const Color(0xFF37474F),
      serviceFeePesewas: serviceFeePesewas,
      materialsFeePesewas: materialsFeePesewas,
      totalPesewas: totalPesewas,
      walletBalancePesewas: (data['walletBalancePesewas'] as num?)?.toInt() ?? 0,
    );
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
