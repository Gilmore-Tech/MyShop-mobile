import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for user-related endpoints beyond auth.
/// EDD § 5.2 — Users (saved locations, emergency contacts)
class UserService {
  UserService(this._dio);
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

  /// GET /users/me/saved-locations — Get saved locations.
  Future<List<dynamic>> getSavedLocations() async {
    try {
      final response = await _dio.get('/users/me/saved-locations');
      return _unwrap(response) as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PUT /users/me — Update profile (can include saved locations in body).
  Future<Map<String, dynamic>> updateSavedLocation({
    required String label,
    required double lat,
    required double lng,
    String? address,
  }) async {
    try {
      final response = await _dio.put('/users/me', data: {
        'savedLocations': [
          {
            'label': label,
            'lat': lat,
            'lng': lng,
            if (address != null) 'address': address,
          }
        ],
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /users/me/emergency-contacts — Get emergency contacts.
  Future<List<dynamic>> getEmergencyContacts() async {
    try {
      final response = await _dio.get('/users/me/emergency-contacts');
      return _unwrap(response) as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
