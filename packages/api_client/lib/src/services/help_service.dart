import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../models/api_exception.dart';

/// REST client for the help-article CMS.
///
/// All endpoints accept an `audience` query param (`client | provider`)
/// so the backend filters articles per app. Search is server-side —
/// the mobile debounces input and sends `q`.
class HelpService {
  HelpService(this._dio);

  final Dio _dio;

  /// `GET /support/help/categories?audience=…` — top-level cards on
  /// the support home.
  Future<List<HelpCategory>> listCategories({
    required SupportAudience audience,
  }) async {
    try {
      final response = await _dio.get(
        '/support/help/categories',
        queryParameters: {'audience': audience.wire},
      );
      final data = _unwrap(response);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(HelpCategory.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /support/help/categories/:slug/articles?audience=…` — article
  /// summaries under a category. The `bodyMarkdown` field is intentionally
  /// omitted on this list — fetch via [getArticle] when the user opens one.
  Future<List<HelpArticle>> listArticles({
    required String categorySlug,
    required SupportAudience audience,
  }) async {
    try {
      final response = await _dio.get(
        '/support/help/categories/$categorySlug/articles',
        queryParameters: {'audience': audience.wire},
      );
      final data = _unwrap(response);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(HelpArticle.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /support/help/articles/:slug?audience=…` — full article
  /// (populates [HelpArticle.bodyMarkdown]).
  Future<HelpArticle> getArticle({
    required String slug,
    required SupportAudience audience,
  }) async {
    try {
      final response = await _dio.get(
        '/support/help/articles/$slug',
        queryParameters: {'audience': audience.wire},
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Article not found.',
        );
      }
      return HelpArticle.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /support/help/search?q=&audience=` — full-text search.
  /// Caller is responsible for debouncing and a min-2-char gate.
  Future<List<HelpArticle>> searchArticles({
    required String query,
    required SupportAudience audience,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    try {
      final response = await _dio.get(
        '/support/help/search',
        queryParameters: {
          'q': trimmed,
          'audience': audience.wire,
        },
      );
      final data = _unwrap(response);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(HelpArticle.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  dynamic _unwrap(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic> && body['success'] == true) {
      return body['data'];
    }
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }
}
