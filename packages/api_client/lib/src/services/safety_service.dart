import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for safety/emergency API endpoints.
/// EDD § 5.2 — POST /emergency
class SafetyService {
  SafetyService(this._dio);
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

  /// POST /emergency — Trigger emergency event.
  /// PRD § 9.1 — Two-step confirmation, GPS + admin alert + police call.
  Future<Map<String, dynamic>> triggerEmergency({
    required String bookingType,
    required String bookingId,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await _dio.post('/emergency', data: {
        'bookingType': bookingType,
        'bookingId': bookingId,
        'lat': lat,
        'lng': lng,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
