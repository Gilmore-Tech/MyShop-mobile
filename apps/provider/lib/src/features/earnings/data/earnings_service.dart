import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

/// Hard cap on every earnings GET. Without this the screen sits on a
/// full-screen spinner for the global Dio timeout (60s) when the backend
/// is slow or unreachable. 15s is generous for a cached endpoint and
/// surfaces as a retryable error UI instead of a long spin.
const Duration _kEarningsRequestTimeout = Duration(seconds: 15);

/// Service for fetching provider earnings + payouts from the backend.
///
/// Wraps the three earnings endpoints:
///   - `GET /payments/earnings/today-card?role=…`
///   - `GET /payments/earnings/summary?period=…&role=…`
///   - `GET /payments/earnings/report?{period|from+to}&granularity=…&role=…`
///
/// Plus the role-agnostic payouts list endpoint:
///   - `GET /payments/payouts`
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
  // Payouts list (history view only — request flow removed)
  // ────────────────────────────────────────────────────────────────────────

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
        'GET $path returned an unexpected response envelope',
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
        'type=${e.type.name}',
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
