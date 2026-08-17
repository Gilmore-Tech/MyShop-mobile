import 'package:dio/dio.dart';

import '../models/api_exception.dart';

class CashCommissionRemittanceStatus {
  const CashCommissionRemittanceStatus({
    required this.remitId,
    required this.status,
    required this.amountPesewas,
    required this.owedPesewas,
    this.gatewayStatus,
    this.completedAt,
  });

  factory CashCommissionRemittanceStatus.fromJson(Map<String, dynamic> json) {
    final remitId = json['remitId'];
    final status = json['status'];
    final amount = json['amountPesewas'];
    final owed = json['owedPesewas'];
    if (remitId is! String ||
        status is! String ||
        amount is! num ||
        owed is! num) {
      throw const FormatException(
        'Invalid cash-commission remittance response',
      );
    }
    final completedAtRaw = json['completedAt'];
    return CashCommissionRemittanceStatus(
      remitId: remitId,
      status: status,
      amountPesewas: amount.toInt(),
      owedPesewas: owed.toInt(),
      gatewayStatus: json['gatewayStatus'] as String?,
      completedAt:
          completedAtRaw is String ? DateTime.tryParse(completedAtRaw) : null,
    );
  }

  final String remitId;
  final String status;
  final String? gatewayStatus;
  final int amountPesewas;
  final int owedPesewas;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isTerminal => isCompleted || isFailed;
}

enum ProviderWithdrawalGroupStatus {
  queued,
  processing,
  partialSuccess,
  needsReview,
  completed,
  unknown;

  static ProviderWithdrawalGroupStatus parse(String raw) {
    return switch (raw) {
      'queued' => ProviderWithdrawalGroupStatus.queued,
      'processing' => ProviderWithdrawalGroupStatus.processing,
      'partial_success' => ProviderWithdrawalGroupStatus.partialSuccess,
      'needs_review' => ProviderWithdrawalGroupStatus.needsReview,
      'completed' => ProviderWithdrawalGroupStatus.completed,
      _ => ProviderWithdrawalGroupStatus.unknown,
    };
  }
}

enum ProviderWithdrawalReviewReason {
  none,
  payoutDestinationReview,
  transferFailed,
  transferReversed,
  withdrawalRecordsReview,
  withdrawalRequiresReview,
  unknown;

  static ProviderWithdrawalReviewReason parse(Object? raw) {
    return switch (raw) {
      null => ProviderWithdrawalReviewReason.none,
      'PAYOUT_DESTINATION_REVIEW' =>
        ProviderWithdrawalReviewReason.payoutDestinationReview,
      'TRANSFER_FAILED' => ProviderWithdrawalReviewReason.transferFailed,
      'TRANSFER_REVERSED' => ProviderWithdrawalReviewReason.transferReversed,
      'WITHDRAWAL_RECORDS_REVIEW' =>
        ProviderWithdrawalReviewReason.withdrawalRecordsReview,
      'WITHDRAWAL_REQUIRES_REVIEW' =>
        ProviderWithdrawalReviewReason.withdrawalRequiresReview,
      _ => ProviderWithdrawalReviewReason.unknown,
    };
  }
}

/// Authoritative status for a manual exact-withdrawal group.
///
/// The POST endpoint accepts one provider intent, while the backend preserves
/// reconciliation by selecting immutable exact Payment membership behind one
/// aggregate provider transfer. New groups therefore expose exactly one rail
/// id in [payoutIds], while [paymentCount] remains the selected earning count.
/// A capped multi-id list is accepted only for historical `partial_success`
/// groups created before the aggregate rail contract.
class ProviderWithdrawalStatus {
  const ProviderWithdrawalStatus({
    required this.withdrawalId,
    required this.status,
    required this.rawStatus,
    required this.currency,
    required this.selectedEarningsPesewas,
    required this.deductionsAppliedPesewas,
    required this.transferQueuedPesewas,
    required this.remainingDebtPesewas,
    required this.paymentCount,
    required this.payoutIds,
    this.reviewReason = ProviderWithdrawalReviewReason.none,
  });

  factory ProviderWithdrawalStatus.fromJson(
    Map<String, dynamic> json, {
    bool allowUnknownStatus = false,
  }) {
    final withdrawalId = json['withdrawalId'];
    final rawStatus = json['status'];
    final currency = json['currency'];
    final selected = json['selectedEarningsPesewas'];
    final deductions = json['deductionsAppliedPesewas'];
    final queued = json['transferQueuedPesewas'];
    final debt = json['remainingDebtPesewas'];
    final paymentCount = json['paymentCount'];
    final rawPayoutIds = json['payoutIds'];
    final reviewReason = ProviderWithdrawalReviewReason.parse(
      json['reasonCode'],
    );

    if (withdrawalId is! String ||
        withdrawalId.trim().isEmpty ||
        rawStatus is! String ||
        rawStatus.trim().isEmpty ||
        currency != 'GHS' ||
        selected is! int ||
        selected < 0 ||
        selected > maxSafeJsonInteger ||
        deductions is! int ||
        deductions < 0 ||
        deductions > maxSafeJsonInteger ||
        queued is! int ||
        queued <= 0 ||
        queued > maxSafeJsonInteger ||
        debt is! int ||
        debt < 0 ||
        debt > maxSafeJsonInteger ||
        paymentCount is! int ||
        paymentCount <= 0 ||
        paymentCount > maxSafeJsonInteger ||
        rawPayoutIds is! List) {
      throw const FormatException('Invalid provider withdrawal response');
    }

    final parsedStatus = ProviderWithdrawalGroupStatus.parse(rawStatus);
    if (!allowUnknownStatus &&
        parsedStatus == ProviderWithdrawalGroupStatus.unknown) {
      throw const FormatException('Unknown provider withdrawal status');
    }
    if (deductions > selected || queued != selected - deductions) {
      throw const FormatException(
        'Provider withdrawal amounts do not conserve selected earnings',
      );
    }
    if (debt != 0) {
      throw const FormatException(
        'A transfer-bearing withdrawal cannot retain remaining debt',
      );
    }

    final payoutIds = <String>[];
    for (final rawId in rawPayoutIds) {
      if (rawId is! String || rawId.trim().isEmpty) {
        throw const FormatException('Invalid provider withdrawal payout id');
      }
      payoutIds.add(rawId);
    }
    final payoutIdLimit =
        paymentCount < maxPayoutIds ? paymentCount : maxPayoutIds;
    if (payoutIds.length > payoutIdLimit) {
      throw const FormatException(
        'Withdrawal payout id count exceeds the response cap',
      );
    }
    if (payoutIds.isEmpty ||
        (parsedStatus != ProviderWithdrawalGroupStatus.partialSuccess &&
            payoutIds.length != 1)) {
      throw const FormatException(
        'Aggregate withdrawal must identify exactly one payout rail',
      );
    }
    if (parsedStatus != ProviderWithdrawalGroupStatus.needsReview &&
        reviewReason != ProviderWithdrawalReviewReason.none) {
      throw const FormatException(
        'Withdrawal review reason is only valid for needs_review',
      );
    }

    return ProviderWithdrawalStatus(
      withdrawalId: withdrawalId,
      status: parsedStatus,
      rawStatus: rawStatus,
      currency: currency as String,
      selectedEarningsPesewas: selected,
      deductionsAppliedPesewas: deductions,
      transferQueuedPesewas: queued,
      remainingDebtPesewas: debt,
      paymentCount: paymentCount,
      payoutIds: List.unmodifiable(payoutIds),
      reviewReason: reviewReason,
    );
  }

  static const maxPayoutIds = 25;
  static const maxSafeJsonInteger = 9007199254740991;

  final String withdrawalId;
  final ProviderWithdrawalGroupStatus status;
  final String rawStatus;
  final String currency;
  final int selectedEarningsPesewas;
  final int deductionsAppliedPesewas;
  final int transferQueuedPesewas;
  final int remainingDebtPesewas;
  final int paymentCount;
  final List<String> payoutIds;
  final ProviderWithdrawalReviewReason reviewReason;

  bool get isTerminal =>
      status == ProviderWithdrawalGroupStatus.partialSuccess ||
      status == ProviderWithdrawalGroupStatus.needsReview ||
      status == ProviderWithdrawalGroupStatus.completed;
}

/// Service for payment API endpoints.
/// EDD § 5.2 — Payments (6 endpoints)
class PaymentService {
  PaymentService(this._dio);
  final Dio _dio;

  dynamic _unwrap(Response response) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) return body['data'];
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }

  /// POST /payments/initiate — Initiate a Paystack charge.
  ///
  /// Matches apps/api/src/modules/payment/dto/initiate-payment.dto.ts on
  /// the backend. Accepted [paymentMethod] values:
  ///   momo_mtn | momo_telecel | momo_airteltigo | visa | mastercard
  ///
  /// [momoPhone] is required for MoMo methods (accepts `+233XXXXXXXXX` or
  /// `0XXXXXXXXX`). [cardToken] is required for card charges on saved
  /// cards; omit it on first-time card payments and Paystack returns a
  /// hosted checkout URL in the response.
  Future<Map<String, dynamic>> initiatePayment({
    required String bookingType,
    required String bookingId,
    required String paymentMethod,
    String? momoPhone,
    String? cardToken,
    String? promoCode,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/initiate',
        data: {
          'bookingType': bookingType,
          'bookingId': bookingId,
          'paymentMethod': paymentMethod,
          if (momoPhone != null) 'momoPhone': momoPhone,
          if (cardToken != null) 'cardToken': cardToken,
          if (promoCode != null) 'promoCode': promoCode,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/acknowledge-cash — Tell the backend the client has
  /// arrived at the payment screen and selected Cash. Sets
  /// `job.clientPaymentAcknowledgedAt`/`job.clientPaymentMethod` and emits
  /// `job:client_payment_acknowledged` to the artisan room. Without this
  /// call the artisan's `POST /jobs/:id/artisan-confirm-cash` will 409 with
  /// `CLIENT_PAYMENT_NOT_ACKNOWLEDGED` — the gate that prevents an artisan
  /// from marking a job paid before the client has even opened the payment
  /// screen.
  ///
  /// Idempotent: hitting it twice returns the same timestamp. Errors:
  ///   400 JOB_NOT_AWAITING_PAYMENT — job isn't `artisan_marked_complete`
  Future<Map<String, dynamic>> acknowledgeCash({
    required String bookingType,
    required String bookingId,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/acknowledge-cash',
        data: {'bookingType': bookingType, 'bookingId': bookingId},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/submit-otp — Forward an OTP for a Paystack MoMo charge
  /// that returned `data.status === 'send_otp'` from /payments/initiate.
  ///
  /// The backend should proxy this to Paystack's `/charge/submit_otp`
  /// endpoint with `{ otp, reference }` and surface the resulting
  /// `data.status` (typically `pay_offline` or `success` after the OTP).
  Future<Map<String, dynamic>> submitOtp({
    required String reference,
    required String otp,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/submit-otp',
        data: {'reference': reference, 'otp': otp},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Send a code to the client-entered MoMo destination for a cash-origin
  /// dispute. The backend reuses the active code when the user explicitly
  /// changes between SMS and WhatsApp.
  Future<Map<String, dynamic>> requestCashRefundDestinationOtp({
    required String disputeId,
    required String method,
    required String accountNumber,
    required String channel,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/refund-destination/request-otp',
        data: {
          'disputeId': disputeId,
          'method': method,
          'accountNumber': accountNumber,
          'channel': channel,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Verify the six-digit code and snapshot the exact refund destination.
  Future<Map<String, dynamic>> verifyCashRefundDestinationOtp({
    required String disputeId,
    required String code,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/refund-destination/verify-otp',
        data: {'disputeId': disputeId, 'code': code},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Read only the masked destination state; the raw number is never returned.
  Future<Map<String, dynamic>> getCashRefundDestinationStatus(
    String disputeId,
  ) async {
    try {
      final response = await _dio.get(
        '/payments/refund-destination/$disputeId',
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /payments/:id/status — Payment status check.
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) async {
    try {
      final response = await _dio.get('/payments/$paymentId/status');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/:paymentId/abandon — Cancel an in-flight Paystack
  /// charge. Use the local payment UUID (from the /initiate response),
  /// NOT the Paystack reference. Idempotent: a 200 comes back even if
  /// the payment is already failed. Errors:
  ///   400 PAYMENT_NOT_ABANDONABLE — payment is escrowed/completed
  ///   403 NOT_YOUR_PAYMENT
  ///   404 PAYMENT_NOT_FOUND
  /// On success the booking is unlocked and the next /payments/initiate
  /// for the same job goes through immediately.
  Future<Map<String, dynamic>> abandonPayment(String paymentId) async {
    try {
      final response = await _dio.post('/payments/$paymentId/abandon');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/abandon-by-booking — Abandon any in-flight pending /
  /// processing payment for a booking when we don't have the paymentId
  /// locally (typical after an app restart that wiped the OTP-flow state).
  ///
  /// Idempotent: returns `{status: 'no_pending_payment'}` when there's
  /// nothing to clear, so it's safe to call unconditionally before
  /// /payments/initiate to belt-and-braces guard against the booking-lock
  /// 409. Refuses escrowed/completed/disputed payments — those need
  /// /payments/:paymentId/dispute instead.
  Future<Map<String, dynamic>> abandonByBooking({
    required String bookingType,
    required String bookingId,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/abandon-by-booking',
        data: {'bookingType': bookingType, 'bookingId': bookingId},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ── Payment Methods ───────────────────────────────────────────────────────────

  /// GET /payment-methods — List the user's saved payment methods.
  Future<List<dynamic>> getPaymentMethods() async {
    try {
      final response = await _dio.get('/payment-methods');
      final data = _unwrap(response);
      if (data is List) return data;
      if (data is Map<String, dynamic> && data['methods'] is List) {
        return data['methods'] as List<dynamic>;
      }
      return [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return [];
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payment-methods/momo — Save a mobile money account.
  Future<Map<String, dynamic>> addMomoMethod({
    required String provider,
    required String phone,
  }) async {
    try {
      final response = await _dio.post(
        '/payment-methods/momo',
        data: {'provider': provider, 'phone': phone},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /payment-methods/:id/default — Set a payment method as default.
  Future<void> setDefaultMethod(String id) async {
    try {
      await _dio.patch('/payment-methods/$id/default');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /payment-methods/:id — Remove a payment method.
  Future<void> deletePaymentMethod(String id) async {
    try {
      await _dio.delete('/payment-methods/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/:id/tip — Add tip post-completion (zero commission).
  Future<Map<String, dynamic>> addTip(
    String paymentId, {
    required int amountPesewas,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/$paymentId/tip',
        data: {'amountPesewas': amountPesewas},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/payout-method/request-otp — provider sends OTP to a
  /// candidate MoMo number before locking it in as the payout destination.
  ///
  /// `method` is one of `momo_mtn`, `momo_telecel`, `momo_airteltigo`.
  /// `accountNumber` accepts either `0XXXXXXXXX` or `+233XXXXXXXXX`;
  /// backend normalises before storage.
  ///
  /// Returns `{ expiresAt, retryAfterSeconds }`. Once a provider has
  /// verified a payout method, this endpoint returns 409
  /// `PAYOUT_METHOD_LOCKED` until an admin unlocks it.
  Future<Map<String, dynamic>> requestPayoutMethodOtp({
    required String method,
    required String accountNumber,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/payout-method/request-otp',
        data: {'method': method, 'accountNumber': accountNumber},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/payout-method/verify-otp — consume the SMS code and
  /// commit the payout method atomically. Returns
  /// `{ payoutMethod, payoutAccountNumber, payoutLocked }`. Wrong codes
  /// decrement attemptsLeft (starts at 5); exhausting them is fatal and
  /// the candidate is destroyed — the provider must request a new OTP.
  Future<Map<String, dynamic>> verifyPayoutMethodOtp({
    required String code,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/payout-method/verify-otp',
        data: {'code': code},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/payouts/request — disburse the provider's available
  /// balance to their stored MoMo. `method` must match the provider's
  /// `payoutMethod` (set via the OTP-verified bind flow above).
  /// `amountPesewas` is optional — omit for full available balance.
  ///
  /// `idempotencyKey` is passed in the `Idempotency-Key` header. Subsequent
  /// calls with the same key replay the first response verbatim for 24 h —
  /// safe to retry on network error without double-disbursing.
  Future<Map<String, dynamic>> requestPayout({
    required String method,
    int? amountPesewas,
    String? idempotencyKey,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/payouts/request',
        data: {
          'method': method,
          if (amountPesewas != null) 'amountPesewas': amountPesewas,
        },
        options: idempotencyKey == null
            ? null
            : Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/payouts/withdraw — request withdrawal of the exact
  /// server-authored withdrawable balance.
  ///
  /// This endpoint never accepts a client-selected payout amount. The value is
  /// an optimistic-concurrency assertion against the latest earnings summary;
  /// the backend re-reads eligible exact Payment rows and either accepts the
  /// current amount or rejects the stale request. A unique idempotency key is
  /// mandatory because a transport timeout may occur after the server accepts
  /// the withdrawal group.
  Future<ProviderWithdrawalStatus> withdrawProviderEarnings({
    required int expectedWithdrawablePesewas,
    required String idempotencyKey,
  }) async {
    if (expectedWithdrawablePesewas <= 0) {
      throw ArgumentError.value(
        expectedWithdrawablePesewas,
        'expectedWithdrawablePesewas',
        'must be positive',
      );
    }
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'must not be empty',
      );
    }

    try {
      final response = await _dio.post(
        '/payments/payouts/withdraw',
        data: {'expectedWithdrawablePesewas': expectedWithdrawablePesewas},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      if (response.statusCode != 202) {
        throw const FormatException(
          'Withdrawal response was not an accepted request',
        );
      }
      final raw = _unwrap(response);
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid provider withdrawal envelope');
      }
      return ProviderWithdrawalStatus.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /payments/payouts/withdrawals/:id — authoritative aggregate-transfer
  /// group status created by [withdrawProviderEarnings].
  Future<ProviderWithdrawalStatus> getProviderWithdrawalStatus(
    String withdrawalId,
  ) async {
    final normalizedId = withdrawalId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        withdrawalId,
        'withdrawalId',
        'must not be empty',
      );
    }
    try {
      final response = await _dio.get(
        '/payments/payouts/withdrawals/${Uri.encodeComponent(normalizedId)}',
      );
      final raw = _unwrap(response);
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid provider withdrawal envelope');
      }
      return ProviderWithdrawalStatus.fromJson(
        raw,
        allowUnknownStatus: true,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/:id/retry — re-initiate a failed MoMo payment after
  /// the client tops up their wallet (PRD edge case #22). Returns the
  /// new payment-initiation envelope, same shape as `initiatePayment`.
  ///
  /// 400 `PAYMENT_NOT_RETRYABLE` means the payment is in a terminal state
  /// (completed, refunded) or the retry window expired.
  Future<Map<String, dynamic>> retryPayment(String paymentId) async {
    try {
      final response = await _dio.post('/payments/$paymentId/retry');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /payments/cash-commission/owed — provider's outstanding
  /// commission debt (sum of pending CASH_COMMISSION clawbacks minus
  /// any partial remits, net of unused provider credits). Drives the
  /// dashboard button swap: when `owedPesewas > 0` the CTA flips to
  /// "Pay Commission" instead of "Request Payout".
  Future<Map<String, dynamic>> getCashCommissionOwed() async {
    try {
      final response = await _dio.get('/payments/cash-commission/owed');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/cash-commission/remit — provider charges their own
  /// MoMo to pay back commission debt. Partial payment is allowed, but the
  /// amount cannot exceed the backend's fresh provider-scoped owed balance.
  /// The Paystack flow mirrors a normal MoMo collection — the provider
  /// receives a USSD push to authorise the charge.
  ///
  /// [idempotencyKey] is mandatory and identifies the complete request body.
  /// A transport retry must reuse the same key and body so an accepted charge
  /// cannot be initiated twice. A changed intent must use a new key.
  ///
  /// 400 codes:
  ///   - `NO_CASH_COMMISSION_OWED` — debt is already zero
  ///   - `INVALID_AMOUNT` — amount ≤ 0
  ///   - `AMOUNT_EXCEEDS_OWED` — the submitted balance snapshot is stale
  ///   - `IDEMPOTENCY_KEY_REQUIRED` — missing/empty durable intent identity
  /// 409 codes:
  ///   - `IDEMPOTENCY_MISMATCH` — key was reused with a changed body
  ///   - `CASH_COMMISSION_REMIT_IN_PROGRESS` — another key is in flight
  Future<Map<String, dynamic>> remitCashCommission({
    required int amountPesewas,
    required String paymentMethod,
    required String momoPhone,
    required String idempotencyKey,
  }) async {
    if (amountPesewas <= 0) {
      throw ArgumentError.value(
        amountPesewas,
        'amountPesewas',
        'must be positive',
      );
    }
    final normalizedIdempotencyKey = idempotencyKey.trim();
    if (normalizedIdempotencyKey.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'must not be empty',
      );
    }

    try {
      final response = await _dio.post(
        '/payments/cash-commission/remit',
        data: {
          'amountPesewas': amountPesewas,
          'paymentMethod': paymentMethod,
          'momoPhone': momoPhone,
        },
        options: Options(
          headers: {'Idempotency-Key': normalizedIdempotencyKey},
        ),
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/cash-commission/remittances/:id/submit-otp — forward the
  /// MoMo OTP/voucher for a remit charge that returned
  /// `chargeStatus === 'send_otp'` from /payments/cash-commission/remit.
  ///
  /// The backend proxies the code to Paystack `/charge/submit_otp` for the
  /// remittance's own reference (the client-payment /payments/submit-otp
  /// endpoint cannot serve remittances). Returns the advanced `chargeStatus`
  /// (typically `pay_offline` — the approval prompt then arrives) plus
  /// `displayText` for the next-step message.
  ///
  /// Error codes:
  ///   - 400 `REMIT_NOT_AWAITING_OTP` — remittance already settled/failed
  ///   - 404 `CASH_COMMISSION_REMIT_NOT_FOUND` — not the caller's remittance
  ///   - 502 `OTP_SUBMISSION_FAILED` — Paystack rejected the code
  Future<Map<String, dynamic>> submitCashCommissionRemitOtp({
    required String remittanceId,
    required String otp,
  }) async {
    try {
      final encodedId = Uri.encodeComponent(remittanceId);
      final response = await _dio.post(
        '/payments/cash-commission/remittances/$encodedId/submit-otp',
        data: {'otp': otp},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /payments/cash-commission/remittances/:id — reads the provider-owned
  /// remittance state. The backend verifies in-flight references with Paystack,
  /// so this also repairs a missed or environment-misdirected webhook.
  Future<CashCommissionRemittanceStatus> getCashCommissionRemittanceStatus(
    String remittanceId,
  ) async {
    try {
      final encodedId = Uri.encodeComponent(remittanceId);
      final response = await _dio.get(
        '/payments/cash-commission/remittances/$encodedId',
      );
      return CashCommissionRemittanceStatus.fromJson(
        _unwrap(response) as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
