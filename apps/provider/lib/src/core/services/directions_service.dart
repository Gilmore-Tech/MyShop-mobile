import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/maps_config.dart';

/// Driving route between two points as returned by Google's Directions API.
///
/// `polyline` is the list of [LatLng] points that, when drawn on a
/// `GoogleMap`, traces the roads between origin and destination. Falls back
/// to a straight two-point line when the API is unavailable so the map
/// never renders an empty route.
class DirectionsRoute {
  const DirectionsRoute({
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isFallback = false,
  });

  final List<LatLng> polyline;
  final int distanceMeters;
  final int durationSeconds;

  /// True when this route was synthesised locally (straight line) because
  /// the Directions API call didn't land.
  final bool isFallback;

  double get distanceKm => distanceMeters / 1000.0;
  int get durationMinutes => (durationSeconds / 60).round();
}

/// Thin wrapper around Google Maps Directions API.
///
/// https://developers.google.com/maps/documentation/directions
///
/// Driving mode since artisans typically drive to the job site. The
/// Directions API toggle must be enabled on the Google Cloud project,
/// otherwise the call fails with REQUEST_DENIED and the caller falls back
/// to the straight-line route.
class DirectionsService {
  DirectionsService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 6),
              ),
            );

  final Dio _dio;
  bool _hasLoggedFailure = false;

  Future<DirectionsRoute> fetchRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (MapsConfig.apiKey.isEmpty) {
      return _fallback(origin, destination);
    }
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': 'driving',
          'key': MapsConfig.apiKey,
        }),
      );
      final data = response.data;
      if (data == null || data['status'] != 'OK') {
        throw StateError(
          'Directions API returned status=${data?['status']}',
        );
      }
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        return _fallback(origin, destination);
      }
      final route = routes.first as Map<String, dynamic>;
      final overviewPolyline =
          route['overview_polyline'] as Map<String, dynamic>?;
      final encoded = overviewPolyline?['points'] as String?;
      final polyline = encoded != null && encoded.isNotEmpty
          ? _decodePolyline(encoded)
          : <LatLng>[origin, destination];

      // Directions returns an array of legs; with no waypoints we only
      // have one, so read its distance/duration directly.
      final legs = route['legs'] as List<dynamic>?;
      final leg = (legs != null && legs.isNotEmpty)
          ? legs.first as Map<String, dynamic>
          : const <String, dynamic>{};
      final distance =
          ((leg['distance'] as Map<String, dynamic>?)?['value'] as num?)
                  ?.toInt() ??
              _haversineMeters(origin, destination).round();
      final duration =
          ((leg['duration'] as Map<String, dynamic>?)?['value'] as num?)
                  ?.toInt() ??
              0;

      return DirectionsRoute(
        polyline: polyline,
        distanceMeters: distance,
        durationSeconds: duration,
      );
    } catch (error, stack) {
      if (!_hasLoggedFailure) {
        _hasLoggedFailure = true;
        developer.log(
          'Directions API failed — falling back to straight-line route. '
          'Enable the Directions API on the Google Cloud project or pass '
          '--dart-define=GOOGLE_MAPS_API_KEY=... to silence this.',
          name: 'DirectionsService',
          error: error,
          stackTrace: stack,
        );
      }
      return _fallback(origin, destination);
    }
  }

  DirectionsRoute _fallback(LatLng origin, LatLng destination) {
    return DirectionsRoute(
      polyline: [origin, destination],
      distanceMeters: _haversineMeters(origin, destination).round(),
      durationSeconds: 0,
      isFallback: true,
    );
  }

  /// Decode a Google-encoded polyline string into a list of [LatLng].
  /// Reference implementation from Google's docs — avoids pulling in a
  /// transitive dependency just for this one function.
  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;
    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Great-circle distance in meters — used only when the Directions API
  /// doesn't provide a distance value.
  double _haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 + s2 * s2 * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  double _toRadians(double deg) => deg * math.pi / 180.0;
}

final directionsServiceProvider = Provider<DirectionsService>((ref) {
  return DirectionsService();
});
