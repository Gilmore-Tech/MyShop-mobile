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
  /// Records an SOS and GPS before the app opens the OS police dialer.
  /// A successful API response does not prove contact delivery or a connected call.
  ///
  /// Wire keys are `latitude` / `longitude` (full names). The earlier
  /// `lat` / `lng` shorthand was rejected with a 400 from the backend's
  /// class-validator DTO, which silently broke every emergency tap.
  Future<Map<String, dynamic>> triggerEmergency({
    String? bookingType,
    String? bookingId,
    double? latitude,
    double? longitude,
  }) async {
    if ((bookingType == null) != (bookingId == null)) {
      throw ArgumentError(
        'bookingType and bookingId must be supplied together',
      );
    }
    if ((latitude == null) != (longitude == null)) {
      throw ArgumentError('latitude and longitude must be supplied together');
    }
    try {
      final response = await _dio.post(
        '/emergency',
        data: {
          if (bookingType != null) 'bookingType': bookingType,
          if (bookingId != null) 'bookingId': bookingId,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
