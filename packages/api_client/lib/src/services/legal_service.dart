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
        throw const ApiException(message: 'Document not found.');
      }
      return LegalDocument.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Public registration authority. Returns exactly the current effective
  /// Terms and Privacy records for the selected role.
  Future<RequiredLegalDocuments> getRequired({required String role}) async {
    try {
      final response = await _dio.get(
        '/legal/required',
        queryParameters: {'role': role},
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(message: 'Legal documents are unavailable.');
      }
      return RequiredLegalDocuments.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<LegalConsentStatus> getConsentStatus() async {
    try {
      final response = await _dio.get('/legal/consent/status');
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw _malformedConsentStatus();
      }
      return _parseConsentStatus(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<LegalConsentStatus> acceptCurrent(
    List<LegalAcceptanceSelection> acceptances,
  ) async {
    try {
      final response = await _dio.post(
        '/legal/consent',
        data: {
          'acceptances': acceptances
              .map((acceptance) => acceptance.toJson())
              .toList(growable: false),
        },
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw _malformedConsentStatus();
      }
      return _parseConsentStatus(data);
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

  /// Legal gating is fail-closed on the backend, but the mobile router must
  /// never infer non-compliance from a malformed response. Require the fields
  /// that decide navigation to be explicit and correctly typed.
  LegalConsentStatus _parseConsentStatus(Map<String, dynamic> data) {
    final role = data['role'];
    if (role is! String ||
        (role != 'client' && role != 'driver' && role != 'artisan') ||
        data['current'] is! bool ||
        data['requiresConsent'] is! bool ||
        data['hasActiveWork'] is! bool ||
        data['missingSlugs'] is! List ||
        !(data['missingSlugs'] as List).every(
          (value) => value is String && value.trim().isNotEmpty,
        ) ||
        data['documents'] is! List ||
        !(data['documents'] as List).every(
          (value) => value is Map<String, dynamic>,
        )) {
      throw _malformedConsentStatus();
    }
    try {
      return LegalConsentStatus.fromJson(data);
    } catch (_) {
      throw _malformedConsentStatus();
    }
  }

  NetworkException _malformedConsentStatus() {
    return const NetworkException(
      message: 'Service temporarily unavailable. Please try again in a moment.',
      kind: NetworkFailureKind.unavailable,
    );
  }
}
