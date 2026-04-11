import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/maps_config.dart';

/// Thin wrapper around Google's Roads API "Snap to Roads" endpoint.
///
/// https://developers.google.com/maps/documentation/roads/snap
///
/// We use this to pin the driver's car marker to the nearest road segment so
/// the marker glides along streets instead of drifting across building
/// rooftops as raw GPS is prone to do.
///
/// Behaviour:
///   * If the Roads API call succeeds, returns the snapped [LatLng].
///   * If the API is not enabled, the key is wrong, or the network is down,
///     returns `null` and the caller should fall back to the raw GPS fix.
///   * The first failure is logged once so ops can notice when the key /
///     billing isn't configured; subsequent failures stay quiet to avoid
///     flooding the log while the driver is online.
class RoadSnapService {
  RoadSnapService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
              ),
            );

  final Dio _dio;
  bool _hasLoggedFailure = false;

  Future<LatLng?> snap(LatLng point) async {
    if (MapsConfig.apiKey.isEmpty) return null;
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        Uri.https('roads.googleapis.com', '/v1/snapToRoads', {
          'path': '${point.latitude},${point.longitude}',
          'interpolate': 'false',
          'key': MapsConfig.apiKey,
        }),
      );
      final data = response.data;
      if (data == null) return null;

      final snapped = data['snappedPoints'] as List<dynamic>?;
      if (snapped == null || snapped.isEmpty) return null;

      final first = snapped.first as Map<String, dynamic>;
      final location = first['location'] as Map<String, dynamic>?;
      if (location == null) return null;

      final lat = (location['latitude'] as num?)?.toDouble();
      final lng = (location['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return LatLng(lat, lng);
    } catch (error, stack) {
      if (!_hasLoggedFailure) {
        _hasLoggedFailure = true;
        developer.log(
          'Roads API snap-to-roads failed — falling back to raw GPS. '
          'Enable the Roads API on the Google Cloud project or pass '
          '--dart-define=GOOGLE_MAPS_API_KEY=... to silence this.',
          name: 'RoadSnapService',
          error: error,
          stackTrace: stack,
        );
      }
      return null;
    }
  }
}

final roadSnapServiceProvider = Provider<RoadSnapService>((ref) {
  return RoadSnapService();
});
