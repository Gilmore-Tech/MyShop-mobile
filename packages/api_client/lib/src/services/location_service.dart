import 'package:dio/dio.dart';

import '../models/api_exception.dart';

enum LocationUnavailableReason {
  permissionLost('permission_lost'),
  serviceDisabled('service_disabled'),
  backgroundPermissionLost('background_permission_lost'),
  gpsUnavailable('gps_unavailable');

  const LocationUnavailableReason(this.wireValue);
  final String wireValue;
}

/// One GPS fix captured by the provider app.
///
/// Driver batches use this shape so active-trip movement can be persisted even
/// when the app is backgrounded and Socket.IO is disconnected.
class DriverLocationSample {
  const DriverLocationSample({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.sampleSequence,
    this.recordedAt,
    this.heading,
    this.speedKmh,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final int sampleSequence;
  final DateTime? recordedAt;
  final double? heading;
  final double? speedKmh;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'sampleSequence': sampleSequence,
      if (recordedAt != null) 'recordedAt': recordedAt!.toIso8601String(),
      if (heading != null) 'heading': heading,
      if (speedKmh != null) 'speedKmh': speedKmh,
    };
  }
}

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
    required double accuracyMeters,
    required DateTime recordedAt,
    String? onlineSessionId,
    int? sampleSequence,
    String status = 'online',
  }) async {
    try {
      final response = await _dio.post(
        '/location/artisan/update',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracyMeters': accuracyMeters,
          'recordedAt': recordedAt.toIso8601String(),
          if (onlineSessionId != null) 'onlineSessionId': onlineSessionId,
          if (sampleSequence != null) 'sampleSequence': sampleSequence,
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
    required double accuracyMeters,
    required DateTime recordedAt,
    String? onlineSessionId,
    int? sampleSequence,
    String? vehicleId,
    String status = 'online',
  }) async {
    try {
      final response = await _dio.post(
        '/location/update',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracyMeters': accuracyMeters,
          'recordedAt': recordedAt.toIso8601String(),
          if (onlineSessionId != null) 'onlineSessionId': onlineSessionId,
          if (sampleSequence != null) 'sampleSequence': sampleSequence,
          if (vehicleId != null) 'vehicleId': vehicleId,
          'status': status,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /location/driver/batch — persist one or more driver GPS fixes.
  ///
  /// The latest sample updates the driver's matcher location and heartbeat.
  /// During an in-progress ride the backend appends each accepted sample to the
  /// trip trail, preserving distance/fare continuity while the screen is off.
  Future<Map<String, dynamic>> updateDriverLocationBatch({
    required List<DriverLocationSample> samples,
    required String onlineSessionId,
  }) async {
    try {
      final response = await _dio.post(
        '/location/driver/batch',
        data: {
          'onlineSessionId': onlineSessionId,
          'samples': samples.map((sample) => sample.toJson()).toList(),
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /location/unavailable — durably removes this provider from new
  /// dispatch while allowing already-active work to follow the server policy.
  Future<Map<String, dynamic>> reportUnavailable(
    LocationUnavailableReason reason,
  ) async {
    try {
      final response = await _dio.post(
        '/location/unavailable',
        data: {'reason': reason.wireValue},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
