import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for rating API endpoints.
/// EDD § 5.2 — POST /ratings (blind 24h window)
class RatingService {
  RatingService(this._dio);
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

  /// POST /ratings — Submit rating (blind 24h window).
  /// PRD § 9.4 — Ratings revealed only after both submit or window closes.
  Future<Map<String, dynamic>> submitRating({
    required String bookingType,
    required String bookingId,
    required int stars,
    String? comment,
  }) async {
    try {
      final response = await _dio.post(
        '/ratings',
        data: {
          'bookingType': bookingType,
          'bookingId': bookingId,
          'stars': stars,
          if (comment != null) 'comment': comment,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /ratings/me — Authenticated user's ratings summary as a ratee.
  ///
  /// Role-agnostic: works for clients (ratings drivers/artisans gave them)
  /// and providers (combined view across booking types). Providers who
  /// want role-scoped numbers should hit `/providers/me/ratings?role=...`
  /// — that endpoint stays gated to driver/artisan and powers the
  /// per-role dashboard tiles.
  ///
  /// Returns `{ average, count, last30dAverage, distribution }`.
  Future<Map<String, dynamic>> getMyRatings() async {
    try {
      final response = await _dio.get('/ratings/me');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
