import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

/// Minimum available balance (pesewas) the backend will allow a payout for.
///
/// Mirrors `payout.service.ts` `minPayoutPesewas` (default 1000p / GHS 10).
/// Backend remains authoritative; this is only used to pre-disable the
/// payout button so users don't tap into a guaranteed 400.
const int kMinPayoutPesewas = 1000;

/// Hard cap on every earnings GET. Without this the screen sits on a
/// full-screen spinner for the global Dio timeout (60s) when the backend
/// is slow or unreachable. 15s is generous for a cached endpoint and
/// surfaces as a retryable error UI instead of a long spin.
const Duration _kEarningsRequestTimeout = Duration(seconds: 15);

/// Service for fetching provider earnings + payouts from the backend.
///
/// Wraps the three new earnings endpoints:
///   - `GET /payments/earnings/today-card?role=…`
///   - `GET /payments/earnings/summary?period=…&role=…`
///   - `GET /payments/earnings/report?{period|from+to}&granularity=…&role=…`
///
/// Plus the role-agnostic payouts endpoints:
///   - `GET /payments/payouts`
///   - `POST /payments/payouts/request`
///
/// All money values are int pesewas (100 pesewas = ₵1).
class EarningsService {
  EarningsService(this._dio);

  final Dio _dio;

  // ────────────────────────────────────────────────────────────────────────
  // Today-card — homepage
  // ────────────────────────────────────────────────────────────────────────

  /// Fetches the homepage "Today's earnings" card. Hot path: hit on every
  /// app open by every active provider, server-cached for 60s.
  Future<EarningsTodayCard> getTodayCard({required EarningsRole role}) async {
    final body = await _get(
      '/payments/earnings/today-card',
      query: {'role': role.wire},
      tag: 'today-card',
    );
    return EarningsTodayCard.fromJson(body);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Summary — earnings tab top card
  // ────────────────────────────────────────────────────────────────────────

  /// Fetches the earnings tab's top "Available balance" card for [period].
  /// Server-cached for 5 minutes; invalidated on every payment status flip.
  Future<EarningsSummary> getSummary({
    required EarningsRole role,
    required EarningsPeriod period,
  }) async {
    final body = await _get(
      '/payments/earnings/summary',
      query: {'period': period.wire, 'role': role.wire},
      tag: 'summary',
    );
    return EarningsSummary.fromJson(body);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Report — detailed report view
  // ────────────────────────────────────────────────────────────────────────

  /// Fetches the detailed report (gross/net/commission/tips/avg-fare + full
  /// graph). Pass either [query.period] (preset) OR [query.from]+[query.to]
  /// (custom range, capped at 90 days server-side).
  Future<EarningsReport> getReport(EarningsReportQuery query) async {
    final params = <String, dynamic>{'role': query.role.wire};
    if (query.isPreset) {
      params['period'] = query.period!.wire;
    } else {
      params['from'] = _ymd(query.from!);
      params['to'] = _ymd(query.to!);
      if (query.granularity != null) {
        params['granularity'] = query.granularity!.wire;
      }
    }
    final body = await _get(
      '/payments/earnings/report',
      query: params,
      tag: 'report',
    );
    return EarningsReport.fromJson(body);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Payouts (role-agnostic for now — backend ticket pending for dual-role)
  // ────────────────────────────────────────────────────────────────────────

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

  /// Fetch the provider's recent payouts (most recent first, capped at 50
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

  // ────────────────────────────────────────────────────────────────────────
  // Internals
  // ────────────────────────────────────────────────────────────────────────

  /// Shared GET helper — unwraps the `{success, data}` envelope, decodes
  /// machine-readable error codes into [EarningsApiException] so screens can
  /// surface specific UX (e.g. range-too-large inline error).
  Future<Map<String, dynamic>> _get(
    String path, {
    required Map<String, dynamic> query,
    required String tag,
  }) async {
    try {
      final response = await _dio
          .get(path, queryParameters: query)
          .timeout(_kEarningsRequestTimeout);
      final body = response.data;
      if (body is Map<String, dynamic> &&
          body['success'] == true &&
          body['data'] is Map<String, dynamic>) {
        return body['data'] as Map<String, dynamic>;
      }
      developer.log(
        'GET $path → unexpected envelope: $body',
        name: 'Earnings.$tag',
        level: 900,
      );
      throw const EarningsApiException(code: 'UNKNOWN');
    } on TimeoutException {
      developer.log(
        'GET $path timed out after ${_kEarningsRequestTimeout.inSeconds}s',
        name: 'Earnings.$tag',
        level: 1000,
      );
      throw const EarningsApiException(
        code: 'TIMEOUT',
        message: "Taking too long to load. Check your connection and retry.",
      );
    } on DioException catch (e) {
      developer.log(
        'GET $path failed: status=${e.response?.statusCode} '
        'body=${e.response?.data} message=${e.message}',
        name: 'Earnings.$tag',
        level: 1000,
      );
      throw _earningsExceptionFromDio(e);
    }
  }

  EarningsApiException _earningsExceptionFromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final envelope = data['error'];
      final source = envelope is Map<String, dynamic> ? envelope : data;
      final code = (source['code'] ?? source['errorCode']) as String?;
      final message = source['message'] as String?;
      if (code != null) {
        return EarningsApiException(code: code, message: message);
      }
    }
    return const EarningsApiException(
      code: 'NETWORK',
      message: 'Connection lost — please try again.',
    );
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

  static String _ymd(DateTime d) {
    final utc = d.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
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
