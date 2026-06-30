import 'package:dio/dio.dart';

import '../models/api_exception.dart';
import '../models/region_dtos.dart';

/// Service for the public regions endpoint.
/// See `docs/region-mobile-handoff.md` — used by provider signup to let a
/// provider pick their home region.
class RegionService {
  RegionService(this._dio);
  final Dio _dio;

  /// GET /v1/regions — Public list of active regions (no bearer token).
  /// Server-cached ~5 min. Returns an empty list on 404 so older backends
  /// degrade gracefully — provider signup then omits `regionId` and the
  /// backend defaults to the active pilot region.
  Future<List<Region>> getRegions() async {
    try {
      // baseUrl already ends in `/v1` — use a root-relative path like every
      // other service ('/categories', '/auth/register'). '/v1/regions' would
      // resolve to '.../v1/v1/regions' and 404.
      final response = await _dio.get('/regions');
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      final regions = data?['regions'] as List<dynamic>? ?? const [];
      return regions
          .map((e) => Region.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      throw ApiException.fromDioException(e);
    }
  }
}
