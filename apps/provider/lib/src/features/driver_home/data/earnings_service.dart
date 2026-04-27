import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

/// Minimum available balance (pesewas) the backend will allow a payout for.
///
/// Mirrors `payout.service.ts` `minPayoutPesewas` (default 1000p / GHS 10).
/// Backend remains authoritative; this is only used to pre-disable the
/// payout button so users don't tap into a guaranteed 400.
const int kMinPayoutPesewas = 1000;

/// Service for fetching provider earnings + payouts from the backend.
///
/// Wraps `GET /payments/earnings?period=…` and `GET /payments/payouts`
/// (see `apps/api/src/modules/payment/payment.controller.ts`).
class EarningsService {
  EarningsService(this._dio);

  final Dio _dio;

  /// Fetch a single period's summary. Used by the home-screen card which
  /// only renders today's totals.
  Future<DriverEarnings> getEarnings({String period = 'today'}) async {
    final response = await _dio.get(
      '/payments/earnings',
      queryParameters: {'period': period},
    );
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true && body['data'] != null) {
      return DriverEarnings.fromJson(body['data'] as Map<String, dynamic>);
    }
    throw Exception('Failed to load earnings');
  }

  /// Fetch today's and this-week's summaries in one round-trip and merge
  /// them. The backend's per-period endpoint only returns one period at a
  /// time, so the dashboard needs two calls — kicked in parallel.
  ///
  /// Falls back to whichever side resolved successfully when the other
  /// errors, rather than failing the whole dashboard. Returns
  /// [DriverEarnings.empty] only when both calls error.
  Future<DriverEarnings> getEarningsAggregate() async {
    final results = await Future.wait<Map<String, dynamic>?>([
      _fetchPeriodRaw('today'),
      _fetchPeriodRaw('week'),
    ]);
    final today = results[0];
    final week = results[1];
    if (today == null && week == null) return DriverEarnings.empty;
    return DriverEarnings.fromBackendPeriods(
      today: today ?? const {},
      week: week ?? today ?? const {},
    );
  }

  Future<Map<String, dynamic>?> _fetchPeriodRaw(String period) async {
    try {
      final response = await _dio.get(
        '/payments/earnings',
        queryParameters: {'period': period},
      );
      final body = response.data as Map<String, dynamic>;
      if (body['success'] == true && body['data'] is Map<String, dynamic>) {
        return body['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Request an instant MoMo payout for the provider's full available
  /// balance.
  ///
  /// Backend (`POST /payments/payouts/request`) constraints:
  ///   - `method` must equal the provider's stored `payoutMethod` (the user
  ///     updates that via `PUT /users/me/{driver|artisan}` first).
  ///   - `amountPesewas` is rejected (`PARTIAL_PAYOUT_NOT_SUPPORTED`); always
  ///     omit and let the backend disburse the full escrowed balance.
  ///   - `Idempotency-Key` is required so a tap that retries (e.g. flaky
  ///     network) doesn't double-disburse. Cached for 24h server-side.
  ///
  /// Returns a [PayoutRequestResult] that callers pattern-match on for
  /// success vs role-specific failure UX. Network/parsing failures surface
  /// as `errorCode = 'NETWORK'`.
  Future<PayoutRequestResult> requestPayout({
    required String method,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _generateIdempotencyKey();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/payments/payouts/request',
        data: {'method': method},
        options: Options(headers: {'Idempotency-Key': key}),
      );
      final body = response.data ?? const <String, dynamic>{};
      if (body['success'] == true && body['data'] is Map<String, dynamic>) {
        return PayoutRequestResult._fromBackend(
          body['data'] as Map<String, dynamic>,
        );
      }
      return const PayoutRequestResult.failure(
        code: 'UNKNOWN',
        message: 'Payout failed. Please try again.',
      );
    } on DioException catch (e) {
      return _payoutFailureFromDio(e);
    } catch (_) {
      return const PayoutRequestResult.failure(
        code: 'NETWORK',
        message: 'Connection lost — please try again.',
      );
    }
  }

  PayoutRequestResult _payoutFailureFromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      // The global filter wraps errors as
      //   { success: false, error: { code, message, details? } }
      // (see apps/api/src/common/filters/http-exception.filter.ts). Older
      // ad-hoc handlers occasionally return a flat shape, so we fall back
      // to top-level keys if the envelope isn't there.
      final envelope = data['error'];
      final source = envelope is Map<String, dynamic> ? envelope : data;
      final rawCode = source['code'] ?? source['errorCode'];
      final code = rawCode is String ? rawCode : null;
      final rawMessage = source['message'];
      final message = rawMessage is String ? rawMessage : null;
      if (code != null) {
        return PayoutRequestResult.failure(
          code: code,
          message: message ?? _payoutMessageFor(code),
        );
      }
    }
    return const PayoutRequestResult.failure(
      code: 'NETWORK',
      message: 'Connection lost — please try again.',
    );
  }

  /// Generates a key unique-per-tap. The backend caches by key for 24h, so
  /// uniqueness only needs to hold within that window — micro-time + 64
  /// bits of entropy is overkill but trivially cheap.
  String _generateIdempotencyKey() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rng = Random.secure();
    final tail = List.generate(
      4,
      (_) => rng.nextInt(0xFFFFFFFF).toRadixString(36),
    ).join();
    return 'mob-$ts-$tail';
  }

  /// Fetch the driver's recent payouts (most recent first, capped at 50
  /// rows by the backend). Returns an empty list rather than throwing
  /// when the endpoint isn't reachable, so the dashboard renders an
  /// empty state instead of an error card.
  Future<List<DriverPayout>> getPayouts() async {
    try {
      final response = await _dio.get('/payments/payouts');
      final body = response.data as Map<String, dynamic>;
      if (body['success'] != true) return const [];
      final raw = body['data'];
      final list = raw is List
          ? raw
          : (raw is Map<String, dynamic> && raw['payouts'] is List
              ? raw['payouts'] as List<dynamic>
              : raw is Map<String, dynamic> && raw['items'] is List
                  ? raw['items'] as List<dynamic>
                  : const <dynamic>[]);
      return list
          .whereType<Map<String, dynamic>>()
          .map(DriverPayout.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

/// Slim model of a payout row — populated from the backend's
/// `GET /payments/payouts` list response.
class DriverPayout {
  const DriverPayout({
    required this.id,
    required this.amountPesewas,
    required this.method,
    required this.status,
    required this.createdAt,
    this.reference,
    this.bookingType,
    this.bookingId,
  });

  factory DriverPayout.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic raw) {
      if (raw is String) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    return DriverPayout(
      id: (json['id'] ?? json['payoutId']) as String? ?? '',
      amountPesewas: (json['amountPesewas'] ??
              json['netPayoutPesewas'] ??
              json['amount']) as num? ??
          0,
      method: (json['method'] ?? json['payoutMethod'] ?? 'momo') as String,
      status: (json['status'] ?? json['payoutStatus'] ?? 'pending') as String,
      createdAt: parseDate(json['createdAt'] ?? json['paidAt']),
      reference: json['reference'] as String?,
      bookingType: json['bookingType'] as String?,
      bookingId: json['bookingId'] as String?,
    );
  }

  final String id;
  final num amountPesewas;
  final String method;
  final String status;
  final DateTime createdAt;
  final String? reference;
  final String? bookingType;
  final String? bookingId;

  String get amountDisplay {
    final ghs = (amountPesewas / 100);
    return '₵${ghs.toStringAsFixed(2)}';
  }
}

/// Outcome of a `POST /payments/payouts/request` call.
///
/// Success carries the new payout's id, status, amount, and (when
/// available) the Paystack reference + ETA so callers can display
/// confirmation copy without an extra fetch. Failure carries the
/// backend's machine-readable [code] (e.g. `NO_PAYOUT_METHOD`,
/// `PAYOUT_IN_PROGRESS`) plus a default user-facing [message] —
/// callers may still substitute their own UX (deep links, confirms).
class PayoutRequestResult {
  const PayoutRequestResult({
    required this.success,
    this.code,
    this.message,
    this.payoutId,
    this.status,
    this.amountPesewas,
    this.reference,
    this.etaSeconds,
  });

  const PayoutRequestResult.failure({required String code, String? message})
      : this(success: false, code: code, message: message);

  factory PayoutRequestResult._fromBackend(Map<String, dynamic> data) {
    return PayoutRequestResult(
      success: true,
      payoutId: data['payoutId'] as String? ?? data['id'] as String?,
      status: data['status'] as String?,
      amountPesewas: (data['amountPesewas'] as num?)?.toInt(),
      reference: data['reference'] as String?,
      etaSeconds: (data['etaSeconds'] as num?)?.toInt(),
    );
  }

  final bool success;
  final String? code;
  final String? message;
  final String? payoutId;
  final String? status;
  final int? amountPesewas;
  final String? reference;
  final int? etaSeconds;

  bool get isFailure => !success;
}

/// Default user-facing copy for each backend error code. Centralised here
/// so both the driver and artisan dashboards render the same wording.
String _payoutMessageFor(String code) {
  switch (code) {
    case 'NO_PAYOUT_METHOD':
      return 'Add a payout method in Account before requesting a payout.';
    case 'PAYOUT_METHOD_MISMATCH':
      return 'Your selected method doesn\'t match the one on file. '
          'Update it in Account first.';
    case 'BANK_TRANSFER_NOT_SUPPORTED':
      return 'Bank transfers aren\'t supported yet — use a MoMo wallet.';
    case 'PAYOUT_IN_PROGRESS':
      return 'A payout is already on the way. Try again once it settles.';
    case 'INSUFFICIENT_BALANCE':
      return 'Your available balance is below the minimum payout (GHS 10).';
    case 'PARTIAL_PAYOUT_NOT_SUPPORTED':
      return 'Partial payouts aren\'t supported — withdraw the full balance.';
    case 'PROVIDER_NOT_FOUND':
      return 'We couldn\'t find your provider profile. Please re-sign in.';
    case 'NETWORK':
      return 'Connection lost — please try again.';
    default:
      return 'Payout failed. Please try again.';
  }
}
