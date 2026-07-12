import 'package:dio/dio.dart';

import '../models/api_exception.dart';

enum ProviderRequestKind { ride, job }

/// A provider-targeted ride/job request that is still actionable.
class ProviderPendingRequest {
  const ProviderPendingRequest({
    required this.kind,
    required this.id,
    this.expiresAt,
    this.payload = const <String, dynamic>{},
  });

  factory ProviderPendingRequest.fromJson(Map<String, dynamic> json) {
    final kind = _kindFromWire(
      json['kind'] as String? ??
          json['type'] as String? ??
          json['bookingType'] as String?,
    );
    final id = json['id'] as String? ??
        json['requestId'] as String? ??
        json['rideId'] as String? ??
        json['jobId'] as String? ??
        '';
    final payloadRaw =
        json['payload'] ?? json['ride'] ?? json['job'] ?? json['booking'];
    return ProviderPendingRequest(
      kind: kind,
      id: id,
      expiresAt: _parseDate(json['expiresAt'] ?? json['expires_at']),
      payload: payloadRaw is Map<String, dynamic>
          ? Map<String, dynamic>.from(payloadRaw)
          : const <String, dynamic>{},
    );
  }

  final ProviderRequestKind kind;
  final String id;
  final DateTime? expiresAt;

  /// Full ride/job payload when the backend has it available. The mobile app
  /// falls back to GET /rides/:id or GET /jobs/:id when this is empty.
  final Map<String, dynamic> payload;

  bool get isExpired {
    final deadline = expiresAt;
    if (deadline == null) return false;
    return !DateTime.now().toUtc().isBefore(deadline.toUtc());
  }

  static ProviderRequestKind _kindFromWire(String? raw) {
    final normalized = raw?.replaceAll('.', '_');
    switch (normalized) {
      case 'ride':
      case 'ride_request':
        return ProviderRequestKind.ride;
      case 'job':
      case 'artisan_job':
      case 'job_request':
        return ProviderRequestKind.job;
      default:
        return ProviderRequestKind.ride;
    }
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }
}

/// REST contract for robust provider request recovery.
///
/// The endpoint is intentionally best-effort in mobile: if an older backend
/// does not expose it yet, callers catch the ApiException and keep the normal
/// socket/FCM flow running.
class ProviderRequestService {
  ProviderRequestService(this._dio);
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

  /// GET /providers/me/pending-requests — returns ride/job requests that the
  /// authenticated driver/artisan can still act on.
  Future<List<ProviderPendingRequest>> listPendingRequests() async {
    try {
      final response = await _dio.get('/providers/me/pending-requests');
      final data = _unwrap(response);
      final raw = _extractList(data);
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ProviderPendingRequest.fromJson)
          .where((r) => r.id.isNotEmpty && !r.isExpired)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final requests = data['requests'] ?? data['items'] ?? data['data'];
      if (requests is List) return requests;
    }
    return const <dynamic>[];
  }
}
