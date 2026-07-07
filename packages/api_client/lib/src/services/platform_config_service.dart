import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Mobile-side reader for runtime business rules persisted in
/// `platform_config` on the backend. Admins flip values like commission
/// rate, payout batch time, surge ceilings via the admin dashboard
/// without a code deploy; mobile reads them from `GET /config/:key`
/// (public, no auth required).
///
/// Keys are namespaced strings (snake_case) — see
/// `apps/api/src/modules/platform-config/platform-config.service.ts`
/// for the allow-list of mutable keys.
class PlatformConfigService {
  PlatformConfigService(this._dio);
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

  /// Reads a single config entry. Returns the raw `value` field — callers
  /// are responsible for parsing (most values are JSON-encoded strings
  /// like `"20"` for numbers, `"true"` for booleans).
  Future<String?> get(String key) async {
    try {
      final response = await _dio.get('/config/$key');
      final data = _unwrap(response) as Map<String, dynamic>;
      final value = data['value'];
      if (value == null) return null;
      return value.toString();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Numeric helper for the common case (commission rate, batch hour,
  /// payout thresholds…). Returns null when the key is missing or the
  /// value can't be parsed — callers should pair with a hard-coded
  /// fallback rather than blocking on a config fetch.
  Future<num?> getNumber(String key) async {
    final raw = await get(key);
    if (raw == null) return null;
    final cleaned = raw.replaceAll('"', '').trim();
    return num.tryParse(cleaned);
  }

  /// Boolean helper for runtime feature flags. Accepts booleans encoded as
  /// JSON/string values (`true`, `"true"`, `1`, `"1"`). Returns null when the
  /// key exists but can't be parsed so callers can fall back safely.
  Future<bool?> getBoolean(String key) async {
    final raw = await get(key);
    if (raw == null) return null;
    final cleaned = raw.replaceAll('"', '').trim().toLowerCase();
    if (cleaned == 'true' || cleaned == '1') return true;
    if (cleaned == 'false' || cleaned == '0') return false;
    return null;
  }
}
