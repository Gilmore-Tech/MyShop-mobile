import 'package:dio/dio.dart';

import '../models/api_exception.dart';

enum ProviderRequestKind { ride, job }

const int maxKnownProviderOfferIds = 100;

/// A provider-targeted ride/job request that is still actionable.
class ProviderPendingRequest {
  const ProviderPendingRequest({
    required this.kind,
    required this.id,
    this.expiresAt,
    this.serverExpiresAt,
    this.offerId,
    this.offerVersion,
    this.payload = const <String, dynamic>{},
  });

  factory ProviderPendingRequest.fromJson(
    Map<String, dynamic> json, {
    Duration transportElapsed = Duration.zero,
  }) {
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
    final payload = payloadRaw is Map<String, dynamic>
        ? Map<String, dynamic>.from(payloadRaw)
        : const <String, dynamic>{};
    final serverExpiresAt = _parseDate(
      json['expiresAt'] ?? json['expires_at'],
    );
    final serverNow = _parseDate(
      json['serverNow'] ?? json['server_now'] ?? payload['serverNow'],
    );
    final expiresAt = _projectDeadlineToDeviceClock(
      serverExpiresAt: serverExpiresAt,
      serverNow: serverNow,
      transportElapsed: transportElapsed,
    );
    return ProviderPendingRequest(
      kind: kind,
      id: id,
      expiresAt: expiresAt,
      serverExpiresAt: serverExpiresAt,
      offerId: (json['offerId'] ?? json['offer_id'] ?? payload['offerId'])
          ?.toString(),
      offerVersion: int.tryParse(
        (json['offerVersion'] ??
                    json['offer_version'] ??
                    payload['offerVersion'])
                ?.toString() ??
            '',
      ),
      payload: payload,
    );
  }

  final ProviderRequestKind kind;
  final String id;
  final DateTime? expiresAt;
  final DateTime? serverExpiresAt;
  final String? offerId;
  final int? offerVersion;

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

  static DateTime? _projectDeadlineToDeviceClock({
    required DateTime? serverExpiresAt,
    required DateTime? serverNow,
    required Duration transportElapsed,
  }) {
    if (serverExpiresAt == null) return null;
    if (serverNow == null) return serverExpiresAt;
    // Both timestamps describe the same server snapshot. Subtracting the
    // complete REST round trip again would make the recovered offer expire
    // early (and double-charge the outbound/server portion of the request).
    final remaining = serverExpiresAt.toUtc().difference(serverNow.toUtc());
    return DateTime.now().toUtc().add(remaining);
  }
}

/// A terminal server-authored result for one exact offer identity previously
/// persisted by the provider device.
class ProviderRequestResolution {
  const ProviderRequestResolution({
    required this.kind,
    required this.offerId,
    required this.state,
    String? requestId,
    String? rideId,
    String? jobId,
    this.resolutionReason,
    this.resolvedAt,
    this.cancelledBy,
  }) : requestId = requestId ?? rideId ?? jobId ?? '';

  factory ProviderRequestResolution.fromJson(Map<String, dynamic> json) {
    final kind = ProviderPendingRequest._kindFromWire(json['kind'] as String?);
    final requestId = kind == ProviderRequestKind.job
        ? (json['jobId'] ?? json['job_id'] ?? json['id'])?.toString()
        : (json['rideId'] ?? json['ride_id'] ?? json['id'])?.toString();
    return ProviderRequestResolution(
      kind: kind,
      offerId: (json['offerId'] ?? json['offer_id'])?.toString() ?? '',
      requestId: requestId ?? '',
      state: json['state']?.toString() ?? '',
      resolutionReason:
          (json['resolutionReason'] ?? json['resolution_reason'])?.toString(),
      resolvedAt: ProviderPendingRequest._parseDate(
        json['resolvedAt'] ?? json['resolved_at'],
      ),
      cancelledBy: (json['cancelledBy'] ?? json['cancelled_by'])?.toString(),
    );
  }

  final ProviderRequestKind kind;
  final String offerId;
  final String requestId;
  final String state;
  final String? resolutionReason;
  final DateTime? resolvedAt;
  final String? cancelledBy;

  String get rideId => kind == ProviderRequestKind.ride ? requestId : '';
  String get jobId => kind == ProviderRequestKind.job ? requestId : '';
}

class ProviderRequestRecoveryResult {
  const ProviderRequestRecoveryResult({
    this.requests = const <ProviderPendingRequest>[],
    this.resolutions = const <ProviderRequestResolution>[],
  });

  final List<ProviderPendingRequest> requests;
  final List<ProviderRequestResolution> resolutions;
}

/// A temporary server-authored pause on receiving new work.
///
/// Every field is additive and nullable so an older backend or a partial
/// rollout cannot make the Provider app fail to load.
class ProviderRequestRestriction {
  const ProviderRequestRestriction({
    this.policyKind,
    this.blockedUntil,
    this.retryAfterSeconds,
    this.count,
    this.points,
    this.threshold,
  });

  factory ProviderRequestRestriction.fromJson(Map<String, dynamic> json) {
    int? integer(Object? value) =>
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

    return ProviderRequestRestriction(
      policyKind: json['policyKind']?.toString(),
      blockedUntil: DateTime.tryParse(
        json['blockedUntil']?.toString() ?? '',
      )?.toUtc(),
      retryAfterSeconds: integer(json['retryAfterSeconds']),
      count: integer(json['count']),
      points: integer(json['points']),
      threshold: integer(json['threshold']),
    );
  }

  final String? policyKind;
  final DateTime? blockedUntil;
  final int? retryAfterSeconds;
  final int? count;
  final int? points;
  final int? threshold;
}

/// Provider-facing response metrics. These are deliberately separate from
/// customer star ratings: declining or missing an offer never mutates rating.
class ProviderRequestResponseSummary {
  const ProviderRequestResponseSummary({
    required this.periodDays,
    required this.eligibleOffers,
    required this.acceptedOffers,
    required this.declinedOffers,
    required this.noResponseOffers,
    this.acceptanceRatePercent,
    this.responseRatePercent,
    this.activeRestriction,
  });

  factory ProviderRequestResponseSummary.fromJson(Map<String, dynamic> json) {
    int integer(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double? percentage(Object? value) {
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 100) {
        return null;
      }
      return parsed;
    }

    final restriction = json['activeRestriction'];
    return ProviderRequestResponseSummary(
      periodDays: integer(json['periodDays']),
      eligibleOffers: integer(json['eligibleOffers']),
      acceptedOffers: integer(json['acceptedOffers']),
      declinedOffers: integer(json['declinedOffers']),
      noResponseOffers: integer(json['noResponseOffers']),
      acceptanceRatePercent: percentage(json['acceptanceRatePercent']),
      responseRatePercent: percentage(json['responseRatePercent']),
      activeRestriction: restriction is Map
          ? ProviderRequestRestriction.fromJson(
              Map<String, dynamic>.from(restriction),
            )
          : null,
    );
  }

  final int periodDays;
  final int eligibleOffers;
  final int acceptedOffers;
  final int declinedOffers;
  final int noResponseOffers;
  final double? acceptanceRatePercent;
  final double? responseRatePercent;
  final ProviderRequestRestriction? activeRestriction;

  bool get hasSample => eligibleOffers > 0;
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
    final result = await recoverPendingRequests();
    return result.requests;
  }

  /// GET /providers/me/request-response-summary.
  ///
  /// Returns null when an older backend has not shipped the endpoint yet.
  /// Other failures remain visible to Riverpod callers, which can render a
  /// neutral unavailable state without showing fabricated percentages.
  Future<ProviderRequestResponseSummary?> getRequestResponseSummary() async {
    try {
      final response = await _dio.get(
        '/providers/me/request-response-summary',
      );
      final data = _unwrap(response);
      if (data is! Map) return null;
      return ProviderRequestResponseSummary.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioException(e);
    }
  }

  /// Reconciles actionable requests plus terminal results for exact offer IDs
  /// this device durably recorded before acknowledging receipt.
  Future<ProviderRequestRecoveryResult> recoverPendingRequests({
    List<String> knownOfferIds = const <String>[],
  }) async {
    final exactOfferIds = knownOfferIds.toSet().toList(growable: false);
    if (exactOfferIds.length > maxKnownProviderOfferIds) {
      throw ArgumentError.value(
        exactOfferIds.length,
        'knownOfferIds',
        'At most $maxKnownProviderOfferIds offer IDs may be reconciled.',
      );
    }
    final transport = Stopwatch()..start();
    try {
      final response = await _dio.get(
        '/providers/me/pending-requests',
        queryParameters: {
          if (exactOfferIds.isNotEmpty)
            'knownOfferIds': exactOfferIds.join(','),
        },
      );
      transport.stop();
      final data = _unwrap(response);
      final requests = _extractList(data)
          .whereType<Map<String, dynamic>>()
          .map(
            (json) => ProviderPendingRequest.fromJson(
              json,
              transportElapsed: transport.elapsed,
            ),
          )
          .where((r) => r.id.isNotEmpty && !r.isExpired)
          .toList(growable: false);
      final resolutions = _extractResolutions(data)
          .whereType<Map<String, dynamic>>()
          .map(ProviderRequestResolution.fromJson)
          .where(
            (resolution) =>
                resolution.offerId.isNotEmpty &&
                resolution.requestId.isNotEmpty &&
                exactOfferIds.contains(resolution.offerId),
          )
          .toList(growable: false);
      return ProviderRequestRecoveryResult(
        requests: requests,
        resolutions: resolutions,
      );
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

  List<dynamic> _extractResolutions(dynamic data) {
    if (data is Map<String, dynamic> && data['resolutions'] is List) {
      return data['resolutions'] as List<dynamic>;
    }
    return const <dynamic>[];
  }
}
