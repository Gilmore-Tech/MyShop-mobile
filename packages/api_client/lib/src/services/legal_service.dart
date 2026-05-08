import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../models/api_exception.dart';

/// REST client for legal documents (terms, privacy, etc.).
///
/// The backend ships the document body as Markdown. For documents that
/// can't reasonably be inlined (third-party license bundles), the
/// response carries `externalUrl` instead of `bodyMarkdown` and the
/// viewer routes the user to the system browser.
class LegalService {
  LegalService(this._dio);

  final Dio _dio;

  /// `GET /legal/:slug?audience=…` — the document. Slugs are listed
  /// in [LegalSlugs.ordered]. The Dio base URL already includes the `/v1`
  /// prefix, so paths here must be unprefixed.
  Future<LegalDocument> getDocument({
    required String slug,
    required SupportAudience audience,
  }) async {
    try {
      final response = await _dio.get(
        '/legal/$slug',
        queryParameters: {'audience': audience.wire},
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Document not found.',
        );
      }
      return LegalDocument.fromJson(data);
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
