import 'package:dio/dio.dart';

/// Wraps `GET /providers/me/ratings` — ratings summary for the
/// authenticated provider.
///
/// Pass `role: 'driver'` or `role: 'artisan'` to scope the aggregate to
/// just that role's bookings. A phone holding both profiles MUST pass
/// the active role — without it the backend returns the combined
/// average across rides AND artisan jobs, which surfaces the same
/// number on both dashboards (the bug reported 14 May).
class RatingsService {
  RatingsService(this._dio);

  final Dio _dio;

  /// Returns the parsed summary on a 2xx with a well-formed envelope.
  /// Lets DioException, FormatException, and unexpected-shape failures
  /// propagate so the caller (a FutureProvider) exposes them as
  /// AsyncError — the dashboard then renders a "Couldn't load ratings"
  /// tile, which is distinct from the legitimate "no ratings yet" state
  /// (count = 0 in a successful response). Conflating the two used to
  /// hide real failures (auth lapse, 5xx, parsing bug) behind the same
  /// silent placeholder as a brand-new provider with zero revealed
  /// ratings.
  Future<ProviderRatingsSummary> getProviderRatings({String? role}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/providers/me/ratings',
      queryParameters: role == null ? null : {'role': role},
    );
    final body = response.data;
    if (body == null ||
        body['success'] != true ||
        body['data'] is! Map<String, dynamic>) {
      throw const FormatException(
        'Unexpected response shape from /providers/me/ratings',
      );
    }
    return ProviderRatingsSummary.fromJson(
      body['data'] as Map<String, dynamic>,
    );
  }
}

/// Aggregated rating summary for the authenticated provider.
class ProviderRatingsSummary {
  const ProviderRatingsSummary({
    required this.average,
    required this.count,
    this.last30dAverage,
    this.distribution = const {},
  });

  factory ProviderRatingsSummary.fromJson(Map<String, dynamic> json) {
    final dist = json['distribution'];
    return ProviderRatingsSummary(
      average: (json['average'] as num?)?.toDouble() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      last30dAverage: (json['last30dAverage'] as num?)?.toDouble(),
      distribution: dist is Map<String, dynamic>
          ? dist.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0))
          : const {},
    );
  }

  static const empty = ProviderRatingsSummary(average: 0, count: 0);

  /// 0–5, one decimal place. `0` when there are no ratings yet.
  final double average;
  final int count;

  /// Same scale as [average] but restricted to the last 30 days. `null`
  /// when there's no recent activity.
  final double? last30dAverage;

  /// Stars → number of ratings (e.g. `{ '5': 12, '4': 3 }`).
  final Map<String, int> distribution;

  bool get hasRatings => count > 0;

  /// "4.8" — display-ready average for the dashboard tile. Empty for the
  /// no-ratings case so callers can fall back to a placeholder string.
  String get averageDisplay => hasRatings ? average.toStringAsFixed(1) : '';
}
