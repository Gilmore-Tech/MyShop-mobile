import 'dart:async';
import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../services/data/pending_payment_store.dart';

// ── Settlement polling ────────────────────────────────────────────────────────
// Webhooks + sockets are the primary driver, but they're unreliable in real
// conditions (battery saver paused the socket, OS killed the WS, the backend
// never re-broadcasts). The screen sits on a spinner forever when that
// happens. The poll is a belt-and-braces fallback that hits
// /payments/:id/status until we see a terminal state or hit the cap.
const _kPollInterval = Duration(seconds: 5);
const _kPollMax = Duration(minutes: 5);

/// Where the ride charge is in its lifecycle.
///
///   idle               → nothing in flight, awaiting user action
///   processing         → /payments/initiate is in flight
///   awaitingOtp        → Paystack returned `send_otp` — collect OTP
///   awaitingSettlement → USSD prompt sent / hosted checkout open;
///                        polling for Paystack to settle the charge
///   settled            → charge succeeded; ready to advance to receipt
///   failed             → charge declined / abandoned / expired
enum RidePaymentPhase {
  idle,
  processing,
  awaitingOtp,
  awaitingSettlement,
  settled,
  failed,
}

/// Surfaced when /payments/initiate returns 409 PAYMENT_ALREADY_INITIATED
/// for a ride. Carries the metadata the screen needs to either let the
/// user wait out [retryAfterSeconds] or trigger a "Cancel & retry" that
/// invokes /payments/abandon-by-booking before re-running /initiate.
class RideStalePaymentAttempt {
  final String paymentId;
  final int ageSeconds;
  final int retryAfterSeconds;

  const RideStalePaymentAttempt({
    required this.paymentId,
    required this.ageSeconds,
    required this.retryAfterSeconds,
  });
}

class RidePaymentState {
  final RidePaymentPhase phase;
  final String? errorMessage;
  final String? authorizationUrl;
  final String? paymentId;
  final String? paystackReference;
  final String? displayText;
  final RideStalePaymentAttempt? staleAttempt;

  const RidePaymentState({
    this.phase = RidePaymentPhase.idle,
    this.errorMessage,
    this.authorizationUrl,
    this.paymentId,
    this.paystackReference,
    this.displayText,
    this.staleAttempt,
  });

  bool get isProcessing => phase == RidePaymentPhase.processing;
  bool get isAwaitingSettlement => phase == RidePaymentPhase.awaitingSettlement;
  bool get isSettled => phase == RidePaymentPhase.settled;

  RidePaymentState copyWith({
    RidePaymentPhase? phase,
    String? errorMessage,
    bool clearError = false,
    String? authorizationUrl,
    bool clearAuthorizationUrl = false,
    String? paymentId,
    String? paystackReference,
    String? displayText,
    bool clearDisplayText = false,
    RideStalePaymentAttempt? staleAttempt,
    bool clearStaleAttempt = false,
  }) =>
      RidePaymentState(
        phase: phase ?? this.phase,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        authorizationUrl: clearAuthorizationUrl
            ? null
            : (authorizationUrl ?? this.authorizationUrl),
        paymentId: paymentId ?? this.paymentId,
        paystackReference: paystackReference ?? this.paystackReference,
        displayText:
            clearDisplayText ? null : (displayText ?? this.displayText),
        staleAttempt:
            clearStaleAttempt ? null : (staleAttempt ?? this.staleAttempt),
      );
}

/// Drives the rider's post-ride Paystack charge for in-app payments.
///
/// Mirrors the artisan-side `PaymentNotifier` (see
/// `apps/client/lib/src/features/services/providers/payment_provider.dart`)
/// but talks to the ride booking type and skips the artisan-only
/// `confirmJobCompletion` step at the end. Ride completion is driven by the
/// driver's PATCH /rides/:id/status; the rider only needs the charge to
/// settle so escrow holds.
class RidePaymentNotifier extends StateNotifier<RidePaymentState> {
  RidePaymentNotifier(this._paymentService, this._pendingStore)
      : super(const RidePaymentState());

  static const _kBookingType = 'ride';

  final PaymentService _paymentService;
  final PendingPaymentStore _pendingStore;

  Timer? _pollTimer;
  DateTime? _pollStartedAt;

  /// Belt-and-braces /payments/abandon-by-booking. Idempotent; logs but
  /// never throws so a network blip can't block /initiate. Run before
  /// retry-/initiate so a stale processing row from a killed prior
  /// attempt can't 409 the fresh charge.
  Future<void> _bestEffortAbandonByBooking(String rideId) async {
    try {
      await _paymentService.abandonByBooking(
        bookingType: _kBookingType,
        bookingId: rideId,
      );
      developer.log('abandonByBooking completed', name: 'RidePayment');
    } on ApiException catch (e) {
      developer.log(
        'ride abandonByBooking failed: ${e.errorCode} — ${e.message}',
        name: 'RidePayment',
        level: 700,
      );
    } catch (e) {
      developer.log('ride abandonByBooking crashed: $e',
          name: 'RidePayment', level: 700);
    }
    await _pendingStore.clear(
      bookingType: _kBookingType,
      bookingId: rideId,
    );
  }

  /// Starts the in-app charge for [rideId]. [paymentMethod] is the wire
  /// value (`momo_mtn` etc.); MoMo methods require [momoPhone].
  ///
  /// When [isRetry] is true (the user just tapped "Retry payment" or
  /// "Cancel & retry") we sweep any stale charge from a previous attempt
  /// via /payments/abandon-by-booking before /initiate to avoid the
  /// 409 booking-lock loop.
  Future<void> initiate({
    required String rideId,
    required String paymentMethod,
    String? momoPhone,
    bool isRetry = false,
  }) async {
    if (state.isProcessing) return;
    if (isRetry) {
      await _bestEffortAbandonByBooking(rideId);
    }
    state = state.copyWith(
      phase: RidePaymentPhase.processing,
      clearError: true,
    );
    try {
      final result = await _paymentService.initiatePayment(
        bookingType: _kBookingType,
        bookingId: rideId,
        paymentMethod: paymentMethod,
        momoPhone: _isMomo(paymentMethod) ? momoPhone : null,
      );
      final authUrl = _findCheckoutUrl(result);
      final paymentId = _findPaymentId(result);
      final paystackReference = _findPaystackReference(result);
      final chargeStatus = _findChargeStatus(result);
      final displayText = _safeRidePaymentPrompt(chargeStatus);
      developer.log(
        'ride payment accepted: hasPaymentId=${paymentId != null} '
        'hasReference=${paystackReference != null} '
        'hasCheckout=${authUrl != null} status=${chargeStatus ?? 'pending'}',
        name: 'RidePayment',
      );

      // Persist the in-flight charge as soon as we know its id — survives
      // an app kill mid-OTP/-USSD so a Retry on the next launch can
      // sweep it via /payments/abandon-by-booking. Cleared on terminal
      // success/failure below.
      if (paymentId != null) {
        await _pendingStore.save(PendingPaymentRecord(
          paymentId: paymentId,
          bookingType: _kBookingType,
          bookingId: rideId,
        ));
      }

      // ── send_otp → pop the OTP sheet ────────────────────────────────
      if (chargeStatus == 'send_otp') {
        if (paystackReference == null) {
          state = state.copyWith(
            phase: RidePaymentPhase.failed,
            errorMessage: "We couldn't continue the payment. Please try again.",
          );
          return;
        }
        state = state.copyWith(
          phase: RidePaymentPhase.awaitingOtp,
          paymentId: paymentId,
          paystackReference: paystackReference,
          displayText: displayText,
        );
        return;
      }

      // ── success → provider accepted the charge, but only an
      // authoritative status read may surface a settled receipt.
      if (chargeStatus == 'success') {
        state = state.copyWith(
          phase: RidePaymentPhase.awaitingSettlement,
          paymentId: paymentId,
          paystackReference: paystackReference,
          displayText: 'Payment accepted. Waiting for final confirmation.',
        );
        _startPolling(paymentId);
        return;
      }

      // ── failed / abandoned → real failure
      if (chargeStatus == 'failed' || chargeStatus == 'abandoned') {
        await _pendingStore.clear(
          bookingType: _kBookingType,
          bookingId: rideId,
        );
        state = state.copyWith(
          phase: RidePaymentPhase.failed,
          errorMessage: 'The payment was declined. Please try again.',
          paymentId: paymentId,
          paystackReference: paystackReference,
        );
        return;
      }

      // ── pay_offline / pending / null → MoMo USSD push or hosted
      // checkout. Wait on the webhook + poll as a belt-and-braces.
      state = state.copyWith(
        phase: RidePaymentPhase.awaitingSettlement,
        authorizationUrl: authUrl,
        paymentId: paymentId,
        paystackReference: paystackReference,
        displayText: displayText,
      );
      _startPolling(paymentId);
    } on ApiException catch (e) {
      developer.log(
        'ride initiatePayment failed: ${e.errorCode} — ${e.message}',
        name: 'RidePayment',
        level: 1000,
      );

      // 409 PAYMENT_ALREADY_INITIATED — the previous charge for this
      // ride is still in flight (kicked the OTP/USSD prompt but hasn't
      // settled). Stash a [RideStalePaymentAttempt] so the screen can
      // pop a "Cancel & retry" dialog with the timing context the
      // backend supplies.
      if (e.errorCode == 'PAYMENT_ALREADY_INITIATED') {
        final stalePaymentId = e.details?['paymentId'] as String?;
        if (stalePaymentId != null) {
          await _pendingStore.save(PendingPaymentRecord(
            paymentId: stalePaymentId,
            bookingType: _kBookingType,
            bookingId: rideId,
          ));
          state = state.copyWith(
            phase: RidePaymentPhase.idle,
            clearError: true,
            staleAttempt: RideStalePaymentAttempt(
              paymentId: stalePaymentId,
              ageSeconds: (e.details?['ageSeconds'] as num?)?.toInt() ?? 0,
              retryAfterSeconds:
                  (e.details?['retryAfterSeconds'] as num?)?.toInt() ?? 0,
            ),
          );
          return;
        }
      }

      state = state.copyWith(
        phase: RidePaymentPhase.failed,
        errorMessage: _friendlyError(e),
      );
    } catch (e) {
      developer.log('ride initiatePayment crashed: $e',
          name: 'RidePayment', level: 1200);
      state = state.copyWith(
        phase: RidePaymentPhase.failed,
        errorMessage: 'Could not start payment. Please try again.',
      );
    }
  }

  /// "Cancel & retry" handler for the ride 409 dialog. Re-runs
  /// [initiate] with `isRetry: true` so the abandon-by-booking sweep
  /// runs first.
  Future<void> abandonStaleAttemptAndRetry({
    required String rideId,
    required String paymentMethod,
    String? momoPhone,
  }) async {
    state = state.copyWith(clearStaleAttempt: true, clearError: true);
    await initiate(
      rideId: rideId,
      paymentMethod: paymentMethod,
      momoPhone: momoPhone,
      isRetry: true,
    );
  }

  /// Dismisses the stale-payment dialog without retrying. The user can
  /// tap "Pay now" again after the backend cron clears the lock.
  void dismissStaleAttempt() {
    state = state.copyWith(clearStaleAttempt: true);
  }

  /// Submit the OTP that came in via SMS for a `send_otp` flow.
  ///
  /// Pass [rideId] when known so terminal failures can clear the
  /// persisted record. Currently the screen always has it.
  Future<void> submitOtp(String otp, {String? rideId}) async {
    final reference = state.paystackReference;
    if (reference == null) {
      state = state.copyWith(
        phase: RidePaymentPhase.failed,
        errorMessage: "We've lost track of this payment. Please start over.",
      );
      return;
    }
    state = state.copyWith(
      phase: RidePaymentPhase.processing,
      clearError: true,
    );
    try {
      final result =
          await _paymentService.submitOtp(reference: reference, otp: otp);
      final chargeStatus = _findChargeStatus(result);
      final displayText = _safeRidePaymentPrompt(chargeStatus);
      switch (chargeStatus) {
        case 'send_otp':
          state = state.copyWith(
            phase: RidePaymentPhase.awaitingOtp,
            errorMessage:
                'That payment code was not accepted. Check it and try again.',
            displayText: displayText,
          );
          return;
        case 'success':
          state = state.copyWith(
            phase: RidePaymentPhase.awaitingSettlement,
            displayText: 'Payment accepted. Waiting for final confirmation.',
          );
          _startPolling(state.paymentId);
          return;
        case 'failed':
        case 'abandoned':
          _stopPolling();
          if (rideId != null) {
            await _pendingStore.clear(
              bookingType: _kBookingType,
              bookingId: rideId,
            );
          }
          state = state.copyWith(
            phase: RidePaymentPhase.failed,
            errorMessage: 'The payment was declined. Please try again.',
            clearAuthorizationUrl: true,
          );
          return;
        default:
          state = state.copyWith(
            phase: RidePaymentPhase.awaitingSettlement,
            authorizationUrl: _findCheckoutUrl(result),
            displayText: displayText,
          );
          _startPolling(state.paymentId);
          return;
      }
    } on ApiException catch (e) {
      switch (e.errorCode) {
        case 'OTP_SUBMISSION_FAILED':
          state = state.copyWith(
            phase: RidePaymentPhase.awaitingOtp,
            errorMessage:
                'That payment code was not accepted. Check it and try again.',
          );
        case 'PAYMENT_NOT_AWAITING_OTP':
          // Race: webhook already settled while user was typing.
          state = state.copyWith(
            phase: RidePaymentPhase.awaitingSettlement,
            clearError: true,
          );
        default:
          state = state.copyWith(
            phase: RidePaymentPhase.failed,
            errorMessage:
                "Couldn't submit the OTP. Please start over and try again.",
          );
      }
    } catch (e) {
      state = state.copyWith(
        phase: RidePaymentPhase.awaitingOtp,
        errorMessage: "Couldn't submit the OTP. Please try again.",
      );
    }
  }

  /// Cancel the in-flight charge and reset to idle. Best-effort — the
  /// backend's stale-payment cron will clear the lock if the abandon call
  /// fails, so the rider can always retry later.
  ///
  /// Pass [rideId] so we can fall back to /payments/abandon-by-booking
  /// when the in-memory paymentId is missing (resumed from a cold start)
  /// and so we can clear the persisted record.
  Future<void> cancel({String? rideId}) async {
    _stopPolling();
    final pid = state.paymentId;
    if (pid != null) {
      try {
        await _paymentService.abandonPayment(pid);
      } catch (_) {/* best-effort */}
    } else if (rideId != null) {
      await _bestEffortAbandonByBooking(rideId);
    }
    if (rideId != null) {
      await _pendingStore.clear(
        bookingType: _kBookingType,
        bookingId: rideId,
      );
    }
    state = const RidePaymentState();
  }

  /// User-triggered authoritative refresh for a delayed payment. A rider tap
  /// can never create a settled receipt from local state.
  Future<void> checkPaymentStatusNow() async {
    if (state.phase != RidePaymentPhase.awaitingSettlement) return;
    final paymentId = state.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      state = state.copyWith(
        errorMessage:
            "We can't check this payment yet. Wait for confirmation or check Activity later.",
      );
      return;
    }
    await _pollOnce(paymentId);
  }

  void resetForRetry() {
    _stopPolling();
    state = state.copyWith(
      phase: RidePaymentPhase.idle,
      clearError: true,
      clearAuthorizationUrl: true,
    );
  }

  /// Failed-phase retry. Tries `POST /payments/:id/retry` first so the
  /// backend's 24-hour insufficient-balance window (Redis-tracked) stays
  /// alive on the same paymentId — that's the path PRD edge case #22
  /// expects when the user tops up MoMo and comes back. If the backend
  /// says the window expired or the payment is not retryable, we fall
  /// back to abandon-by-booking + fresh /initiate so the rider isn't
  /// stuck.
  ///
  /// Caller passes the current [paymentMethod] + [momoPhone] (read from
  /// the screen's selection) so the fallback path can fire /initiate
  /// without re-prompting.
  Future<void> retryAfterFailure({
    required String rideId,
    required String paymentMethod,
    String? momoPhone,
  }) async {
    final pid = state.paymentId;
    if (pid == null) {
      // No payment id known (e.g. the original /initiate never returned
      // one) — straight to fresh /initiate.
      await initiate(
        rideId: rideId,
        paymentMethod: paymentMethod,
        momoPhone: momoPhone,
        isRetry: true,
      );
      return;
    }

    state = state.copyWith(
      phase: RidePaymentPhase.processing,
      clearError: true,
    );
    try {
      final result = await _paymentService.retryPayment(pid);
      developer.log(
        'ride payment retry accepted: '
        'status=${_findChargeStatus(result) ?? 'pending'} '
        'hasCheckout=${_findCheckoutUrl(result) != null}',
        name: 'RidePayment',
      );
      // Backend flips the payment to processing and re-sends the MoMo
      // prompt — same downstream state as a fresh /initiate that landed
      // on `pay_offline`. Poll for settlement.
      state = state.copyWith(
        phase: RidePaymentPhase.awaitingSettlement,
        paymentId: pid,
      );
      _startPolling(pid);
    } on ApiException catch (e) {
      developer.log(
        'ride retryPayment failed: ${e.errorCode} — ${e.message}',
        name: 'RidePayment',
        level: 800,
      );
      // 24h window expired or backend rejects retry on this row — fall
      // through to the abandon-by-booking + /initiate path.
      if (e.errorCode == 'RETRY_WINDOW_EXPIRED' ||
          e.errorCode == 'PAYMENT_NOT_RETRYABLE' ||
          e.errorCode == 'CARD_RETRY_NOT_SUPPORTED') {
        await initiate(
          rideId: rideId,
          paymentMethod: paymentMethod,
          momoPhone: momoPhone,
          isRetry: true,
        );
        return;
      }
      state = state.copyWith(
        phase: RidePaymentPhase.failed,
        errorMessage: _friendlyError(e),
      );
    } catch (e) {
      developer.log('ride retryPayment crashed: $e',
          name: 'RidePayment', level: 1200);
      state = state.copyWith(
        phase: RidePaymentPhase.failed,
        errorMessage: 'Could not retry the payment. Please try again.',
      );
    }
  }

  void _startPolling(String? paymentId) {
    _stopPolling();
    if (paymentId == null) return;
    _pollStartedAt = DateTime.now();
    _pollTimer = Timer.periodic(_kPollInterval, (_) {
      _pollOnce(paymentId);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollStartedAt = null;
  }

  Future<void> _pollOnce(String paymentId) async {
    if (state.phase != RidePaymentPhase.awaitingSettlement) {
      _stopPolling();
      return;
    }
    final startedAt = _pollStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) >= _kPollMax) {
      _stopPolling();
      if (!mounted) return;
      state = state.copyWith(
        errorMessage: "We're still waiting on confirmation from the payment "
            "provider. Check your Activity tab in a few minutes — your "
            'receipt will show up there once it settles.',
      );
      return;
    }
    try {
      final result = await _paymentService.getPaymentStatus(paymentId);
      if (!mounted || state.phase != RidePaymentPhase.awaitingSettlement) {
        return;
      }
      final outcome = _classifyStatus(result);
      switch (outcome) {
        case _PollOutcome.succeeded:
          _stopPolling();
          state = state.copyWith(phase: RidePaymentPhase.settled);
        case _PollOutcome.failed:
          _stopPolling();
          state = state.copyWith(
            phase: RidePaymentPhase.failed,
            errorMessage: 'The payment was declined. Please try again.',
            clearAuthorizationUrl: true,
          );
        case _PollOutcome.keepPolling:
          break;
      }
    } catch (e) {
      // Transient — let the next tick try again.
      developer.log('ride payment poll error: $e',
          name: 'RidePayment', level: 700);
    }
  }

  String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'PAYMENT_ALREADY_SETTLED':
        return 'This trip has already been paid for.';
      // 409 PAYMENT_ALREADY_INITIATED falls through to the same friendly
      // string when the response was missing a paymentId; the typical
      // path is handled above with a [RideStalePaymentAttempt].
      case 'PAYMENT_ALREADY_INITIATED':
        return 'A payment is already in progress for this trip. Check '
            'your phone for an OTP or USSD prompt — if nothing arrives '
            'in a minute or two, the previous attempt will time out and '
            'you can retry.';
      case 'PAYMENT_GATEWAY_ERROR':
        return 'The payment was declined. Check the number and balance '
            'and try again.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: "Couldn't start the payment. Please try again.",
          conflictMessage:
              'The payment state changed. Refresh the trip before trying again.',
        );
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

bool _isMomo(String wire) =>
    wire == 'momo_mtn' || wire == 'momo_telecel' || wire == 'momo_airteltigo';

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

String? _findCheckoutUrl(Object? node) {
  if (node is String) {
    if (node.startsWith('http') &&
        (node.contains('paystack') || node.contains('checkout'))) {
      return node;
    }
    return null;
  }
  if (node is Map) {
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

String? _findChargeStatus(Object? node) {
  if (node is Map) {
    for (final key in const [
      'chargeStatus',
      'charge_status',
      'nextStep',
      'next_step',
    ]) {
      final v = node[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final inner = node['data'];
    if (inner is Map) {
      final s = inner['status'];
      if (s is String && s != 'success' && s.contains('_')) return s;
      if (s is String) return s;
    }
    final flat = node['status'];
    if (flat is String && flat.startsWith('send_')) return flat;
  }
  return null;
}

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

String? _findPaystackReference(Object? node) {
  if (node is Map) {
    for (final key in const [
      'reference',
      'transactionRef',
      'transaction_ref'
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

String? _safeRidePaymentPrompt(String? chargeStatus) {
  return switch (chargeStatus) {
    'send_otp' => 'Enter the payment code sent to your phone.',
    'pay_offline' ||
    'pending' ||
    'processing' =>
      'Approve the payment prompt on your phone, then wait for confirmation.',
    _ => null,
  };
}

final ridePaymentNotifierProvider =
    StateNotifierProvider.autoDispose<RidePaymentNotifier, RidePaymentState>(
  (ref) => RidePaymentNotifier(
    ref.watch(paymentServiceProvider),
    ref.watch(pendingPaymentStoreProvider),
  ),
);
