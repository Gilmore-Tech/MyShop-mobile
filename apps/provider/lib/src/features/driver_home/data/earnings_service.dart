import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

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
