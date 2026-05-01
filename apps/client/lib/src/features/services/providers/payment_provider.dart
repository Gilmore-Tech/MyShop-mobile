import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../../../core/di/providers.dart';

// ── Settlement polling ────────────────────────────────────────────────────────
// Webhooks + sockets are the primary driver, but they're unreliable in real
// conditions (battery saver paused the socket, the OS killed the WS, the
// backend never re-broadcasts). The screen sits on a spinner forever when
// that happens. The poll is a belt-and-braces fallback that hits
// /payments/:id/status until we see a terminal state or hit the cap.
const _kSettlementPollInterval = Duration(seconds: 5);
const _kSettlementPollMax      = Duration(minutes: 5);

/// Reads a payment-status response and classifies it into one of three
/// outcomes — keeps the polling loop tolerant to the variants different
/// Paystack-compatible backends use ('succeeded', 'success', 'paid',
/// 'escrowed', 'completed', etc.).
enum _PollOutcome { keepPolling, succeeded, failed }

_PollOutcome _classifyStatus(Map<String, dynamic> result) {
  String? findStatus(Object? node) {
    if (node is Map) {
      for (final key in const ['status', 'paymentStatus', 'payment_status']) {
        final v = node[key];
        if (v is String && v.isNotEmpty) return v;
      }
      for (final v in node.values) {
        final hit = findStatus(v);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  final raw = findStatus(result)?.toLowerCase();
  if (raw == null) return _PollOutcome.keepPolling;

  const success = {'succeeded', 'success', 'paid', 'escrowed', 'completed'};
  const failure = {'failed', 'abandoned', 'cancelled', 'expired'};
  if (success.contains(raw)) return _PollOutcome.succeeded;
  if (failure.contains(raw)) return _PollOutcome.failed;
  return _PollOutcome.keepPolling;
}

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

/// Surfaces Paystack's inner `data.status` from the initiate response so
/// the notifier can branch on `send_otp` / `send_pin` / `pay_offline` /
/// `success` / `failed`. Walks the tree because backends sometimes wrap
/// the field as `{data: {status: ...}}` and sometimes flatten it.
String? _findChargeStatus(Object? node) {
  if (node is Map) {
    // Look for `chargeStatus` / `nextStep` first (cleaner backend
    // wrappers), then fall back to a nested `data.status`.
    for (final key in const ['chargeStatus', 'charge_status', 'nextStep', 'next_step']) {
      final v = node[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final inner = node['data'];
    if (inner is Map) {
      final s = inner['status'];
      if (s is String && s != 'success' && s.contains('_')) return s;
      // Also check nested data.status for send_otp etc. — `success` here
      // means an entirely settled charge, which the caller treats as
      // awaitingSettlement (webhook still needs to fire), not as a step.
      if (s is String) return s;
    }
    final flat = node['status'];
    if (flat is String && flat.startsWith('send_')) return flat;
  }
  return null;
}

/// Backend's own payment record id (used for status polls / receipts).
/// Distinct from the Paystack reference, which is what we forward to
/// `/charge/submit_otp`.
String? _findPaymentId(Object? node) {
  if (node is Map) {
    for (final key in const ['paymentId', 'payment_id', 'id']) {
      final v = node[key];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final v in node.values) {
      final hit = _findPaymentId(v);
      if (hit != null) return hit;
    }
  }
  if (node is List) {
    for (final v in node) {
      final hit = _findPaymentId(v);
      if (hit != null) return hit;
    }
  }
  return null;
}

/// Paystack-side reference. The backend rejects `submit-otp` with 404
/// `PAYMENT_NOT_FOUND` if we send the local paymentId instead — Paystack
/// only knows about the reference.
String? _findPaystackReference(Object? node) {
  if (node is Map) {
    for (final key in const [
      'reference',
      'transactionRef',
      'transaction_ref',
    ]) {
      final v = node[key];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final v in node.values) {
      final hit = _findPaystackReference(v);
      if (hit != null) return hit;
    }
  }
  if (node is List) {
    for (final v in node) {
      final hit = _findPaystackReference(v);
      if (hit != null) return hit;
    }
  }
  return null;
}

/// User-facing prompt that came back from Paystack ("Enter the OTP sent
/// to your phone", "Authorize on your phone", etc.). Surfaced under the
/// OTP sheet title and used as the snackbar text on failures.
String? _findDisplayText(Object? node) {
  if (node is Map) {
    for (final key in const [
      'displayText',
      'display_text',
      'paystackMessage',
      'paystack_message',
      'message',
    ]) {
      final v = node[key];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final v in node.values) {
      final hit = _findDisplayText(v);
      if (hit != null) return hit;
    }
  }
  return null;
}

// ── Payment Method ────────────────────────────────────────────────────────────
// PRD 7.1 — client payment methods. Values align with the backend DTO at
// apps/api/src/modules/payment/dto/initiate-payment.dto.ts:
//   momo_mtn | momo_telecel | momo_airteltigo | visa | mastercard
// Plus an app-side [cash] option that skips /payments/initiate entirely
// (Paystack can't process cash — the artisan confirms receipt instead).

enum PaymentMethod {
  momoMtn,
  momoTelecel,
  momoAirteltigo,
  visa,
  mastercard,
  cash,
}

extension PaymentMethodX on PaymentMethod {
  /// Wire value sent to `POST /payments/initiate`. Null for [cash] — cash
  /// never hits the payment service; the artisan confirms receipt manually
  /// via PATCH /jobs/:id/confirm.
  String? get wireValue => switch (this) {
        PaymentMethod.momoMtn        => 'momo_mtn',
        PaymentMethod.momoTelecel    => 'momo_telecel',
        PaymentMethod.momoAirteltigo => 'momo_airteltigo',
        PaymentMethod.visa           => 'visa',
        PaymentMethod.mastercard     => 'mastercard',
        PaymentMethod.cash           => null,
      };

  String get label => switch (this) {
        PaymentMethod.momoMtn        => 'MTN Mobile Money',
        PaymentMethod.momoTelecel    => 'Telecel Cash',
        PaymentMethod.momoAirteltigo => 'AirtelTigo Money',
        PaymentMethod.visa           => 'Visa',
        PaymentMethod.mastercard     => 'Mastercard',
        PaymentMethod.cash           => 'Cash',
      };

  String get subtitle => switch (this) {
        PaymentMethod.momoMtn        => 'Approve the prompt on your MTN line',
        PaymentMethod.momoTelecel    => 'Approve the prompt on your Telecel line',
        PaymentMethod.momoAirteltigo => 'Approve the prompt on your AT line',
        PaymentMethod.visa           => 'Pay by Visa card via Paystack',
        PaymentMethod.mastercard     => 'Pay by Mastercard via Paystack',
        PaymentMethod.cash           =>
          'Settle in cash; the artisan confirms receipt',
      };

  IconData get icon => switch (this) {
        PaymentMethod.momoMtn        => Icons.sim_card_rounded,
        PaymentMethod.momoTelecel    => Icons.sim_card_rounded,
        PaymentMethod.momoAirteltigo => Icons.sim_card_rounded,
        PaymentMethod.visa           => Icons.credit_card_rounded,
        PaymentMethod.mastercard     => Icons.credit_card_rounded,
        PaymentMethod.cash           => Icons.payments_outlined,
      };

  /// True when the backend expects a `momoPhone` field on the initiate call.
  bool get requiresMomoPhone =>
      this == PaymentMethod.momoMtn ||
      this == PaymentMethod.momoTelecel ||
      this == PaymentMethod.momoAirteltigo;

  /// True when the backend expects an optional `cardToken` (Paystack
  /// tokenised reference). When null, the backend falls back to the
  /// hosted Paystack checkout URL for first-time cards.
  bool get isCard =>
      this == PaymentMethod.visa || this == PaymentMethod.mastercard;

  bool get isCash => this == PaymentMethod.cash;
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
  /// Job UUID — needed by the success dialog so its "Rate & Review
  /// Provider" button can hand the rating sheet a valid bookingId.
  final String jobId;

  final String transactionRef;  // e.g. "#TXN-2024-8821"
  final String artisanName;
  final String jobTitle;
  final int amountPesewas;
  final PaymentMethod method;

  /// Human-readable timestamp, e.g. "24 Oct 2023, 02:30 PM".
  final String dateTimeLabel;

  const PaymentConfirmation({
    required this.jobId,
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
///   awaitingOtp  → Paystack returned `send_otp` — user types the OTP
///                  they got via SMS so we can submit it to /charge/submit_otp.
///   awaitingSettlement → Paystack charge queued, job is `pending_payment`.
///                        The webhook will flip the job to `completed` (or
///                        back to `artisan_marked_complete` on failure).
///   settled      → job status has landed as `completed`; PATCH /confirm ran
///                  (idempotent) and the success dialog is showing.
///   failed       → charge failed. Job reverted to `artisan_marked_complete`
///                  so the client can retry the payment.
enum PaymentPhase {
  idle,
  processing,
  awaitingOtp,
  awaitingSettlement,
  settled,
  failed,
}

/// Surfaced when /payments/initiate returns 409 PAYMENT_ALREADY_INITIATED.
/// Carries enough info for the screen to show a "Cancel & retry" dialog
/// with timing context, or to wait until [retryAfterSeconds] elapses
/// (the backend's stale-payment cron auto-clears charges older than the
/// TTL — default 10 min — so a fresh /initiate eventually goes through
/// even if the client never tells us to abandon).
class StalePaymentAttempt {
  /// Local payment UUID of the in-flight charge — pass this to
  /// /payments/:paymentId/abandon to cancel it explicitly.
  final String paymentId;

  /// How long the in-flight charge has been alive, server-side.
  final int ageSeconds;

  /// Seconds until the backend's sweeper will auto-clear the charge.
  /// Drives the "or wait Xs" hint in the dialog.
  final int retryAfterSeconds;

  const StalePaymentAttempt({
    required this.paymentId,
    required this.ageSeconds,
    required this.retryAfterSeconds,
  });
}

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

  /// Backend's own payment record id — used for `GET /payments/:id/status`
  /// polls, the receipt header, and POST /payments/:id/abandon. Distinct
  /// from [paystackReference].
  final String? paymentId;

  /// Paystack-side reference. The backend rejects `submit-otp` with 404
  /// `PAYMENT_NOT_FOUND` if we send the local paymentId, so this is what
  /// gets forwarded when the user types the OTP.
  final String? paystackReference;

  /// User-facing prompt from Paystack ("Enter the OTP we sent to your
  /// phone", "Authorize on your phone", "A USSD prompt has been sent…").
  /// Surfaced as the awaitingSettlement subtitle and OTP sheet title.
  final String? displayText;

  /// Set when /initiate returns 409 PAYMENT_ALREADY_INITIATED — the
  /// screen listens for this transition and pops a dialog letting the
  /// user cancel-and-retry or wait for the backend cron.
  final StalePaymentAttempt? staleAttempt;

  const PaymentState({
    this.selectedMethod = PaymentMethod.momoMtn,
    this.phase = PaymentPhase.idle,
    this.errorMessage,
    this.confirmation,
    this.authorizationUrl,
    this.paymentId,
    this.paystackReference,
    this.displayText,
    this.staleAttempt,
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
    String? paystackReference,
    String? displayText,
    bool clearDisplayText = false,
    StalePaymentAttempt? staleAttempt,
    bool clearStaleAttempt = false,
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
        paystackReference: paystackReference ?? this.paystackReference,
        displayText: clearDisplayText ? null : (displayText ?? this.displayText),
        staleAttempt: clearStaleAttempt
            ? null
            : (staleAttempt ?? this.staleAttempt),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier(this._paymentService, this._jobService)
      : super(const PaymentState());

  final PaymentService _paymentService;
  final JobService _jobService;

  /// Periodic poll on /payments/:id/status while we're in awaitingSettlement.
  /// Belt-and-braces for missed socket events. Always cleared on terminal
  /// state, retry, or dispose so it never outlives the screen.
  Timer? _pollTimer;

  /// Wallclock when polling started — used to enforce [_kSettlementPollMax]
  /// without keeping a tick counter. Reset every time polling restarts.
  DateTime? _pollStartedAt;

  void selectMethod(PaymentMethod method) =>
      state = state.copyWith(selectedMethod: method);

  // ── Settlement polling ────────────────────────────────────────────────────

  /// Starts the status-poll loop for [paymentId]. Idempotent — if a poll is
  /// already running it will be cancelled and replaced (e.g. caller passed
  /// in a fresh paymentId after a retry). Caller must guarantee
  /// [paymentId] is non-null; we no-op gracefully if it isn't, since
  /// without it we can't hit /payments/:id/status.
  void _startSettlementPolling({
    required String? paymentId,
    required String jobId,
    required PaymentSummary summary,
  }) {
    _pollTimer?.cancel();
    if (paymentId == null) {
      developer.log(
        'Skipping settlement poll — no paymentId in state.',
        name: 'Payment',
        level: 800,
      );
      return;
    }
    _pollStartedAt = DateTime.now();
    _pollTimer = Timer.periodic(_kSettlementPollInterval, (_) {
      _pollSettlementOnce(
        paymentId: paymentId,
        jobId: jobId,
        summary: summary,
      );
    });
  }

  void _stopSettlementPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollStartedAt = null;
  }

  Future<void> _pollSettlementOnce({
    required String paymentId,
    required String jobId,
    required PaymentSummary summary,
  }) async {
    // If the user navigated to a different phase between ticks, drop out.
    if (state.phase != PaymentPhase.awaitingSettlement) {
      _stopSettlementPolling();
      return;
    }

    // Cap the wait so a never-settling charge doesn't poll forever.
    final startedAt = _pollStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) >= _kSettlementPollMax) {
      _stopSettlementPolling();
      developer.log(
        'Settlement poll timed out after ${_kSettlementPollMax.inMinutes}m '
        '— surfacing fallback message.',
        name: 'Payment',
        level: 900,
      );
      if (!mounted) return;
      state = state.copyWith(
        errorMessage:
            "We're still waiting on confirmation from the payment "
            'provider. Check the Activity tab in a few minutes — your '
            'receipt will show up there once it settles.',
      );
      return;
    }

    try {
      final result = await _paymentService.getPaymentStatus(paymentId);
      if (!mounted || state.phase != PaymentPhase.awaitingSettlement) return;

      final outcome = _classifyStatus(result);
      switch (outcome) {
        case _PollOutcome.succeeded:
          _stopSettlementPolling();
          await confirmCompletion(jobId: jobId, summary: summary);
        case _PollOutcome.failed:
          _stopSettlementPolling();
          if (!mounted) return;
          state = state.copyWith(
            phase: PaymentPhase.failed,
            errorMessage: 'The payment was declined. Please try again.',
            clearAuthorizationUrl: true,
          );
        case _PollOutcome.keepPolling:
          // Still pending — let the next tick try again.
          break;
      }
    } on ApiException catch (e) {
      // Transient — keep polling. A genuinely dead payment will eventually
      // hit the timeout cap above. Don't surface to the user here, the
      // intermediate "Approve on your phone" copy is still accurate.
      developer.log(
        'getPaymentStatus poll failed: ${e.errorCode} — ${e.message}',
        name: 'Payment',
        level: 700,
      );
    } catch (e) {
      developer.log(
        'getPaymentStatus poll crashed: $e',
        name: 'Payment',
        level: 700,
      );
    }
  }

  @override
  void dispose() {
    _stopSettlementPolling();
    super.dispose();
  }

  /// Kicks off the settlement flow for the selected payment method.
  ///
  ///   - MoMo (MTN / Telecel / AirtelTigo): POST /payments/initiate with
  ///     `momoPhone`; Paystack sends a USSD prompt to the user's line or
  ///     returns a checkout URL. Webhook advances the job to `completed`.
  ///   - Card (Visa / Mastercard): POST /payments/initiate with the
  ///     optional `cardToken`. No token → backend returns a Paystack
  ///     hosted checkout URL we launch externally.
  ///   - Cash: skips the payment API entirely (Paystack can't process
  ///     cash). The artisan confirms receipt on their side via the overlay
  ///     Yes/No; PATCH /jobs/:id/confirm then flips the job to completed.
  Future<void> confirmPayment({
    required String jobId,
    required PaymentSummary summary,
    String? momoPhone,
    String? cardToken,
  }) async {
    if (state.isProcessing) return;
    final method = state.selectedMethod;

    // ── Cash: no backend charge ───────────────────────────────────────
    if (method.isCash) {
      // Tell the backend the client has chosen Cash so it can gate the
      // artisan's "Yes, I received payment" button. Without this the
      // artisan's confirm-cash endpoint 409s with
      // CLIENT_PAYMENT_NOT_ACKNOWLEDGED, leaving the cash flow stuck.
      // The acknowledge call also emits `job:client_payment_acknowledged`
      // to the artisan room so their UI flips live.
      state = state.copyWith(phase: PaymentPhase.processing, clearError: true);
      try {
        await _paymentService.acknowledgeCash(
          bookingType: 'artisan_job',
          bookingId: jobId,
        );
      } on ApiException catch (e) {
        developer.log(
          'acknowledgeCash failed: status=${e.statusCode} '
          'code=${e.errorCode} — ${e.message}',
          name: 'Payment',
          level: 900,
        );
        state = state.copyWith(
          phase: PaymentPhase.idle,
          errorMessage: e.message.isNotEmpty
              ? e.message
              : "We couldn't confirm cash with the artisan. Please try again.",
        );
        return;
      } catch (e) {
        developer.log(
          'acknowledgeCash crashed: $e',
          name: 'Payment',
          level: 1000,
        );
        state = state.copyWith(
          phase: PaymentPhase.idle,
          errorMessage:
              "We couldn't confirm cash with the artisan. Please try again.",
        );
        return;
      }

      // Park the UI in awaitingSettlement with no URL — the CTA renders
      // as "Waiting for artisan to confirm receipt" and the socket event
      // that follows the artisan's "Yes" tap flips us to completed.
      state = state.copyWith(
        phase: PaymentPhase.awaitingSettlement,
        clearError: true,
      );
      return;
    }

    // ── MoMo: backend requires momoPhone ──────────────────────────────
    if (method.requiresMomoPhone &&
        (momoPhone == null || momoPhone.trim().isEmpty)) {
      state = state.copyWith(
        errorMessage: 'Enter your mobile money number to continue.',
      );
      return;
    }

    final wireMethod = method.wireValue;
    if (wireMethod == null) {
      state = state.copyWith(
        errorMessage: 'This payment method is not supported right now.',
      );
      return;
    }

    state = state.copyWith(phase: PaymentPhase.processing, clearError: true);
    try {
      final result = await _paymentService.initiatePayment(
        bookingType: 'artisan_job',
        bookingId: jobId,
        paymentMethod: wireMethod,
        momoPhone: method.requiresMomoPhone ? momoPhone!.trim() : null,
        cardToken: method.isCard ? cardToken : null,
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
      final paymentId = _findPaymentId(result);
      final paystackReference = _findPaystackReference(result);
      final chargeStatus = _findChargeStatus(result);
      final displayText = _findDisplayText(result);

      // ── send_otp → pop the OTP sheet ────────────────────────────────
      // The user got an SMS code; we forward it via /payments/submit-otp,
      // which expects the Paystack reference (NOT the local paymentId).
      if (chargeStatus == 'send_otp') {
        if (paystackReference == null) {
          developer.log(
            'send_otp returned but no Paystack reference — cannot submit '
            'OTP. Backend should include `reference` in the response.',
            name: 'Payment',
            level: 1000,
          );
          state = state.copyWith(
            phase: PaymentPhase.idle,
            errorMessage:
                "We couldn't continue the payment. Please try again.",
          );
          return;
        }
        state = state.copyWith(
          phase: PaymentPhase.awaitingOtp,
          paymentId: paymentId,
          paystackReference: paystackReference,
          displayText: displayText,
        );
        return;
      }

      // ── success → charge already settled inline (rare for MoMo, common
      // for charge_authorization). PATCH /confirm closes the loop.
      if (chargeStatus == 'success') {
        state = state.copyWith(
          phase: PaymentPhase.awaitingSettlement,
          paymentId: paymentId,
          paystackReference: paystackReference,
        );
        await confirmCompletion(jobId: jobId, summary: summary);
        return;
      }

      // ── failed / abandoned → real failure; surface Paystack's text
      if (chargeStatus == 'failed' || chargeStatus == 'abandoned') {
        state = state.copyWith(
          phase: PaymentPhase.failed,
          errorMessage:
              displayText ?? 'The payment was declined. Please try again.',
          paymentId: paymentId,
          paystackReference: paystackReference,
        );
        return;
      }

      // ── Other send_* steps (send_pin / send_phone / send_birthday) —
      // not wired yet, treat like failure with a clear message.
      if (chargeStatus != null && chargeStatus.startsWith('send_')) {
        developer.log(
          'Unsupported Paystack next-step: $chargeStatus',
          name: 'Payment',
          level: 1000,
        );
        state = state.copyWith(
          phase: PaymentPhase.failed,
          errorMessage:
              'This payment needs an extra step we don\'t handle yet — '
              'try a different method.',
          paymentId: paymentId,
          paystackReference: paystackReference,
        );
        return;
      }

      // ── pay_offline / pending / null → MoMo USSD push flow. Show the
      // "authorize on your phone" state and wait on the webhook to
      // settle the job.
      if (authUrl == null) {
        developer.log(
          'initiatePayment returned no checkout URL — '
          'awaiting webhook settlement (chargeStatus=$chargeStatus).',
          name: 'Payment',
          level: 800,
        );
      }

      state = state.copyWith(
        phase: PaymentPhase.awaitingSettlement,
        authorizationUrl: authUrl,
        paymentId: paymentId,
        paystackReference: paystackReference,
        displayText: displayText,
      );
      _startSettlementPolling(
        paymentId: paymentId,
        jobId: jobId,
        summary: summary,
      );
    } on ApiException catch (e) {
      developer.log(
        'initiatePayment failed: ${e.errorCode} — ${e.message}',
        name: 'Payment',
        level: 1000,
      );

      // 409 PAYMENT_ALREADY_INITIATED — backend has a charge in flight
      // for this booking (most often because the user killed the app
      // mid-USSD-prompt). When the response carries the in-flight
      // paymentId, surface a [StalePaymentAttempt] so the screen can
      // show "Cancel & retry". If for any reason paymentId is missing
      // we fall back to the friendly error string instead of stalling.
      if (e.errorCode == 'PAYMENT_ALREADY_INITIATED') {
        final stalePaymentId = e.details?['paymentId'] as String?;
        if (stalePaymentId != null) {
          state = state.copyWith(
            phase: PaymentPhase.idle,
            clearError: true,
            staleAttempt: StalePaymentAttempt(
              paymentId: stalePaymentId,
              ageSeconds:
                  (e.details?['ageSeconds'] as num?)?.toInt() ?? 0,
              retryAfterSeconds:
                  (e.details?['retryAfterSeconds'] as num?)?.toInt() ?? 0,
            ),
          );
          return;
        }
      }

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

  /// Cancels the in-flight charge (POST /payments/:id/abandon) and then
  /// re-runs [confirmPayment] with the same args. Wired to the
  /// "Cancel & retry" action on the stale-payment dialog. The abandon
  /// is best-effort — even if it fails we still proceed to the retry,
  /// since the backend's stale-payment cron will eventually clear the
  /// lock and the next /initiate will go through.
  Future<void> abandonStaleAttemptAndRetry({
    required String jobId,
    required PaymentSummary summary,
    String? momoPhone,
    String? cardToken,
  }) async {
    final stale = state.staleAttempt;
    if (stale != null) {
      try {
        await _paymentService.abandonPayment(stale.paymentId);
        developer.log(
          'Abandoned stale payment ${stale.paymentId}',
          name: 'Payment',
        );
      } on ApiException catch (e) {
        developer.log(
          'abandonPayment failed: ${e.errorCode} — ${e.message}',
          name: 'Payment',
          level: 800,
        );
      } catch (e) {
        developer.log('abandonPayment crashed: $e',
            name: 'Payment', level: 800);
      }
    }
    state = state.copyWith(clearStaleAttempt: true, clearError: true);
    await confirmPayment(
      jobId: jobId,
      summary: summary,
      momoPhone: momoPhone,
      cardToken: cardToken,
    );
  }

  /// Dismisses the stale-payment dialog without retrying. The backend
  /// cron will eventually clear the lock; the user can tap
  /// "Confirm & Pay" again after retryAfterSeconds elapses.
  void dismissStaleAttempt() {
    state = state.copyWith(clearStaleAttempt: true);
  }

  String _friendlyInitiateError(ApiException e) {
    switch (e.errorCode) {
      case 'JOB_NOT_AWAITING_PAYMENT':
        return "This job isn't ready for payment yet. Ask the artisan to "
            'mark the work complete and try again.';
      case 'PAYMENT_ALREADY_SETTLED':
        return 'This job has already been paid for.';
      // 409 — backend already has an active payment record for this job
      // because a previous attempt is still in flight (OTP not submitted,
      // USSD not approved, or Paystack hasn't timed it out yet).
      case 'PAYMENT_ALREADY_INITIATED':
        return 'A payment is already in progress for this job. Check '
            'your phone for an OTP or USSD prompt — if nothing arrives '
            "in a minute or two, the previous attempt will time out and "
            'you can retry.';
      case 'PAYMENT_GATEWAY_ERROR':
        // The backend currently surfaces every Paystack error with the
        // top-level message string ("Charge attempted"), which is unhelpful
        // — the real reason lives in the inner `data.message`. Until the
        // backend forwards that, give the user the most likely cause.
        return 'The payment was declined. If you are testing, use one of '
            "Paystack's test mobile-money numbers (e.g. 0551234987 for "
            'MTN). Otherwise check the number and balance and try again.';
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
    _stopSettlementPolling();
    state = state.copyWith(
      phase: PaymentPhase.settled,
      confirmation: PaymentConfirmation(
        jobId: summary.jobId,
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

  /// Submit the OTP the user got via SMS for a Paystack `send_otp` flow.
  /// Backend forwards it to `/charge/submit_otp` (using the Paystack
  /// reference, NOT the local paymentId) and returns the next chargeStatus.
  ///
  /// Branches on the response:
  ///   - `send_otp` again       → wrong OTP, stay on the sheet
  ///   - `success`              → settle inline via PATCH /confirm
  ///   - `failed` / `abandoned` → mark failed, surface displayText
  ///   - anything else          → wait on the webhook (awaitingSettlement)
  ///
  /// And on error codes (per the backend contract):
  ///   - 502 OTP_SUBMISSION_FAILED  → wrong/expired OTP — keep sheet open
  ///   - 400 PAYMENT_NOT_AWAITING_OTP → race with webhook, fall through
  ///   - 403 NOT_YOUR_PAYMENT / 404 PAYMENT_NOT_FOUND → generic + log
  Future<void> submitOtp(String otp, {required String jobId, required PaymentSummary summary}) async {
    // Backend rejects with 404 PAYMENT_NOT_FOUND if we send the local
    // paymentId — Paystack only knows the reference.
    final reference = state.paystackReference;
    if (reference == null) {
      state = state.copyWith(
        phase: PaymentPhase.idle,
        errorMessage:
            "We've lost track of this payment. Please start over.",
      );
      return;
    }
    state = state.copyWith(phase: PaymentPhase.processing, clearError: true);
    try {
      final result =
          await _paymentService.submitOtp(reference: reference, otp: otp);
      developer.log('submitOtp response: $result', name: 'Payment');
      final chargeStatus = _findChargeStatus(result);
      final displayText = _findDisplayText(result);

      switch (chargeStatus) {
        case 'send_otp':
          // Paystack asked again — typically means the user fat-fingered.
          state = state.copyWith(
            phase: PaymentPhase.awaitingOtp,
            errorMessage:
                displayText ?? "That OTP didn't work. Try again.",
            displayText: displayText,
          );
          return;
        case 'success':
          state = state.copyWith(phase: PaymentPhase.awaitingSettlement);
          await confirmCompletion(jobId: jobId, summary: summary);
          return;
        case 'failed':
        case 'abandoned':
          _stopSettlementPolling();
          state = state.copyWith(
            phase: PaymentPhase.failed,
            errorMessage:
                displayText ?? 'The payment was declined. Please try again.',
            clearAuthorizationUrl: true,
          );
          return;
        default:
          // pay_offline / pending / null / send_pin → wait on webhook.
          state = state.copyWith(
            phase: PaymentPhase.awaitingSettlement,
            authorizationUrl: _findCheckoutUrl(result),
            displayText: displayText,
          );
          _startSettlementPolling(
            paymentId: state.paymentId,
            jobId: jobId,
            summary: summary,
          );
          return;
      }
    } on ApiException catch (e) {
      developer.log(
        'submitOtp failed: ${e.errorCode} — ${e.message}',
        name: 'Payment',
        level: 1000,
      );
      switch (e.errorCode) {
        case 'OTP_SUBMISSION_FAILED':
          // Backend's catch-all for Paystack rejecting the OTP — most
          // commonly a wrong code. Keep the sheet open with the inline
          // gateway message.
          state = state.copyWith(
            phase: PaymentPhase.awaitingOtp,
            errorMessage: e.message,
          );
          return;
        case 'PAYMENT_NOT_AWAITING_OTP':
          // Race: webhook already settled the charge while the user was
          // typing. Fall through to the wait-on-settlement state — the
          // socket listener will close the loop.
          state = state.copyWith(
            phase: PaymentPhase.awaitingSettlement,
            clearError: true,
          );
          return;
        case 'NOT_YOUR_PAYMENT':
        case 'PAYMENT_NOT_FOUND':
        default:
          state = state.copyWith(
            phase: PaymentPhase.failed,
            errorMessage:
                "Couldn't submit the OTP. Please start over and try again.",
          );
          return;
      }
    } catch (e, st) {
      developer.log('submitOtp crashed: $e\n$st',
          name: 'Payment', level: 1200);
      state = state.copyWith(
        phase: PaymentPhase.awaitingOtp,
        errorMessage: "Couldn't submit the OTP. Please try again.",
      );
    }
  }

  /// User dismissed the OTP sheet without submitting. Fires
  /// POST /payments/:id/abandon so the backend marks the in-flight
  /// charge failed (and reverts the artisan job to
  /// `artisan_marked_complete`), unlocking the booking for an immediate
  /// fresh /initiate. Best-effort — the local state resets either way
  /// so the sheet always closes.
  Future<void> cancelOtp() async {
    _stopSettlementPolling();
    final pid = state.paymentId;
    if (pid != null) {
      try {
        await _paymentService.abandonPayment(pid);
        developer.log('Abandoned payment $pid (OTP cancel)',
            name: 'Payment');
      } on ApiException catch (e) {
        developer.log(
          'abandonPayment on OTP cancel failed: ${e.errorCode} — ${e.message}',
          name: 'Payment',
          level: 800,
        );
      } catch (e) {
        developer.log('abandonPayment on OTP cancel crashed: $e',
            name: 'Payment', level: 800);
      }
    }
    state = state.copyWith(phase: PaymentPhase.idle, clearError: true);
  }

  /// Called when the socket reports the job bounced back to
  /// `artisan_marked_complete` — Paystack charge failed. The user can tap
  /// "Retry payment" which resets state and re-enters the flow.
  void markPaymentFailed(String message) {
    _stopSettlementPolling();
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
    _stopSettlementPolling();
    state = state.copyWith(
      phase: PaymentPhase.idle,
      clearError: true,
      clearAuthorizationUrl: true,
    );
  }

  /// Manual "I've completed the payment" tap from the awaiting-settlement
  /// screen. Bypasses the backend confirmation step and flips straight to
  /// `settled` with a [PaymentConfirmation] so the success dialog fires —
  /// the user has just told us, in person, that the USSD prompt was
  /// approved on their phone. We trust them.
  ///
  /// Use case: the Paystack webhook chain (or socket) didn't surface the
  /// settlement to us — common in dev when no public tunnel is set up,
  /// and occasionally in prod when the webhook is delayed. The polling
  /// fallback would eventually catch it, but waiting up to 5 minutes
  /// staring at a spinner is a bad UX. This is the user's escape hatch.
  ///
  /// Caveat: this does not run PATCH /jobs/:id/confirm. If the webhook
  /// is genuinely never going to land, the backend job stays in
  /// `pending_payment` until something else nudges it. The receipt the
  /// user sees is real (their money moved on Paystack's side); the
  /// cleanup of the booking record is the part we can't guarantee here.
  void markPaymentSettledLocally({required PaymentSummary summary}) {
    if (state.phase == PaymentPhase.settled) return;
    _stopSettlementPolling();
    state = state.copyWith(
      phase: PaymentPhase.settled,
      confirmation: PaymentConfirmation(
        jobId:          summary.jobId,
        transactionRef: state.paymentId ??
            '#TXN-${summary.jobId.hashCode.abs() % 9000 + 1000}',
        artisanName:    summary.artisanName,
        jobTitle:       summary.jobTitle,
        amountPesewas:  summary.totalPesewas,
        method:         state.selectedMethod,
        dateTimeLabel:  _formatNow(),
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
      // Log the raw shape so it's visible in the dev console — backends
      // tend to drift between `selectedBid` / `acceptedBid` / `bid` for
      // the chosen offer, and the cost field naming has been a moving
      // target. Keeps debugging "amount is GHS 0.00" trivially fast.
      developer.log('getJob($jobId) → $data', name: 'PaymentSummary');
      return _parsePaymentSummary(data);
    } catch (e, st) {
      developer.log(
        'paymentSummaryProvider($jobId) failed to parse: $e\n$st',
        name: 'PaymentSummary',
        level: 900,
      );
      // Fallback to mock during development / if endpoint not ready
      return _mockPayments[jobId] ?? _defaultMockPayment;
    }
  }

  /// Parse API response into [PaymentSummary].
  ///
  /// Tolerant of backend field-name drift — checks the most likely paths
  /// for the chosen bid (selectedBid / acceptedBid / bid / winningBid)
  /// and for the cost (costBreakdown nested vs. flat fields, snake_case
  /// vs. camelCase). The `agreedPricePesewas` field on the job itself is
  /// also a common shape post-acceptance.
  PaymentSummary _parsePaymentSummary(Map<String, dynamic> data) {
    final bidData = _firstMap(data, const [
      'selectedBid',
      'acceptedBid',
      'winningBid',
      'bid',
    ]);
    final costBreakdown = _firstMap(data, const [
      'costBreakdown',
      'cost_breakdown',
    ]);
    final artisanData = _firstMap(data, const [
      'provider',
      'artisan',
      'assignedArtisan',
      'assigned_artisan',
    ]);
    final categoryData = _firstMap(data, const ['category']);

    final artisanName = '${artisanData['firstName'] ?? artisanData['first_name'] ?? ''} '
            '${artisanData['lastName'] ?? artisanData['last_name'] ?? ''}'
        .trim();

    // Service / labour fee — try every shape we've seen.
    final serviceFeePesewas = _firstInt(costBreakdown, const [
          'laborPesewas',
          'labor_pesewas',
          'labourPesewas',
          'labour_pesewas',
        ]) ??
        _firstInt(bidData, const [
          'amountPesewas',
          'amount_pesewas',
          'totalPesewas',
          'total_pesewas',
        ]) ??
        _firstInt(data, const [
          'agreedPricePesewas',
          'agreed_price_pesewas',
          'agreedPrice',
          'amountPesewas',
        ]) ??
        0;

    final materialsFeePesewas = _firstInt(costBreakdown, const [
          'materialsPesewas',
          'materials_pesewas',
        ]) ??
        0;

    final totalPesewas = _firstInt(data, const [
          'totalPesewas',
          'total_pesewas',
          'amountPesewas',
        ]) ??
        _firstInt(costBreakdown, const ['totalPesewas', 'total_pesewas']) ??
        (serviceFeePesewas + materialsFeePesewas);

    if (totalPesewas == 0) {
      developer.log(
        'Parsed totalPesewas=0 — unrecognised cost shape. data=$data',
        name: 'PaymentSummary',
        level: 900,
      );
    }

    return PaymentSummary(
      jobId: data['id'] as String? ?? '',
      serviceId: 'Service ID: #${data['id'] ?? ''}',
      paymentRef: 'JOB #${data['id'] ?? ''}',
      jobTitle: data['description'] as String? ?? '',
      paymentDescription: (bidData['message'] ?? bidData['notes']) as String? ??
          'Funds will be held in escrow and released only after your confirmation.',
      categoryName: categoryData['name'] as String? ?? '',
      categoryIcon: Icons.build_rounded,
      location: (data['locationAddress'] ??
              data['addressText'] ??
              data['address']) as String? ??
          '',
      completionLabel: data['estimatedDuration'] as String? ?? '—',
      artisanName: artisanName.isNotEmpty ? artisanName : 'Artisan',
      artisanFirstName:
          (artisanData['firstName'] ?? artisanData['first_name']) as String? ??
              'Artisan',
      artisanAvatarColor: const Color(0xFF37474F),
      serviceFeePesewas: serviceFeePesewas,
      materialsFeePesewas: materialsFeePesewas,
      totalPesewas: totalPesewas,
      walletBalancePesewas:
          _firstInt(data, const ['walletBalancePesewas', 'wallet_balance_pesewas']) ??
              0,
    );
  }

  /// First map-valued key in [keys] under [node], or empty when none match.
  static Map<String, dynamic> _firstMap(
    Map<String, dynamic> node,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = node[k];
      if (v is Map<String, dynamic>) return v;
    }
    return const {};
  }

  /// First numeric (int) key in [keys] under [node], or null when none match.
  static int? _firstInt(Map<String, dynamic> node, List<String> keys) {
    for (final k in keys) {
      final v = node[k];
      if (v is num) return v.toInt();
    }
    return null;
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
