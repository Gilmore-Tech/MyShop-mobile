import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// REST endpoints for persisting a provider's real-time location.
///
/// The backend's matcher requires `current_location IS NOT NULL` and
/// `online_status = 'online'` before an artisan/driver will be considered
/// for new jobs/rides. These endpoints flip both fields server-side.
///
/// Called in parallel with the socket `location:update` emit so that the
/// DB stays consistent even if the socket listener is delayed or offline.
class LocationService {
  LocationService(this._dio);
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

  /// POST /location/artisan/update — set artisan's current location and
  /// mark them as online.
  Future<Map<String, dynamic>> updateArtisanLocation({
    required double latitude,
    required double longitude,
    String status = 'online',
  }) async {
    try {
      final response = await _dio.post(
        '/location/artisan/update',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'status': status,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /location/update — set driver's current location and mark them
  /// online. Backend is rate-limited to 1 update per 3 seconds and blocks
  /// the call if there's an active ride in progress (`TOGGLE_LOCKED_ACTIVE_RIDE`).
  Future<Map<String, dynamic>> updateDriverLocation({
    required double latitude,
    required double longitude,
    String status = 'online',
  }) async {
    try {
      final response = await _dio.post(
        '/location/update',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'status': status,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
