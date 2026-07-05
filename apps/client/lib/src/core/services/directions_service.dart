import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../di/providers.dart';

/// Driving route returned by the authenticated MyShop backend.
class DirectionsRoute {
  const DirectionsRoute({
    required this.polyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isFallback = false,
    this.warningMessage,
  });

  final List<LatLng> polyline;
  final int distanceMeters;
  final int durationSeconds;

  /// True only when the backend route could not be loaded and the app is
  /// displaying a direct two-point line to keep the destination visible.
  final bool isFallback;

  /// User-facing/loggable explanation for a fallback. This prevents a route
  /// failure from quietly masquerading as valid road routing.
  final String? warningMessage;
}

/// Fetches traffic-aware routes through the authenticated MyShop API.
///
/// The Google Routes key stays on the backend and can therefore be restricted
/// to the Render service's outbound IP addresses. The rider app only keeps its
/// native Maps SDK key for rendering the map itself.
class DirectionsService {
  DirectionsService(this._dio);

  final Dio _dio;
  // Backend waits up to 8s for Google Routes. Keep the mobile timeout longer
  // so the app doesn't cancel first and replace a valid road route with the
  // direct-line fallback while the backend is still computing.
  static const _requestTimeout = Duration(seconds: 10);

  Future<DirectionsRoute> fetchRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final cancelToken = CancelToken();
    final timer = Timer(_requestTimeout, () {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('Route request timed out');
      }
    });
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/location/routes/compute',
        data: {
          'originLatitude': origin.latitude,
          'originLongitude': origin.longitude,
          'destinationLatitude': destination.latitude,
          'destinationLongitude': destination.longitude,
        },
        cancelToken: cancelToken,
        options: Options(
          sendTimeout: _requestTimeout,
          receiveTimeout: _requestTimeout,
        ),
      );
      final responseBody = response.data;
      if (responseBody == null) {
        throw const FormatException('Route response body was empty');
      }
      final data = responseBody['success'] == true &&
              responseBody['data'] is Map<String, dynamic>
          ? responseBody['data'] as Map<String, dynamic>
          : responseBody;

      final encoded = data['polyline'] as String?;
      final distanceMeters = (data['distanceMeters'] as num?)?.toInt();
      final durationSeconds = (data['durationSeconds'] as num?)?.toInt();
      if (encoded == null ||
          encoded.isEmpty ||
          distanceMeters == null ||
          durationSeconds == null) {
        throw const FormatException('Route response was incomplete');
      }

      final polyline = _decodePolyline(encoded);
      if (polyline.length < 2) {
        throw const FormatException('Route polyline was invalid');
      }

      return DirectionsRoute(
        polyline: polyline,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      );
    } catch (error, stack) {
      developer.log(
        'Authenticated route request failed; displaying an explicit direct-line fallback.',
        name: 'DirectionsService',
        error: error,
        stackTrace: stack,
      );
      return _fallback(origin, destination);
    } finally {
      timer.cancel();
    }
  }

  DirectionsRoute _fallback(LatLng origin, LatLng destination) {
    return DirectionsRoute(
      polyline: [origin, destination],
      distanceMeters: _haversineMeters(origin, destination).round(),
      durationSeconds: 0,
      isFallback: true,
      warningMessage: 'Road directions unavailable — showing a direct line.',
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        if (index >= encoded.length) {
          throw const FormatException('Truncated route polyline');
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      latitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        if (index >= encoded.length) {
          throw const FormatException('Truncated route polyline');
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      longitude += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }
    return points;
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h =
        sinLat * sinLat + sinLng * sinLng * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  double _toRadians(double degrees) => degrees * math.pi / 180.0;
}

final directionsServiceProvider = Provider<DirectionsService>((ref) {
  return DirectionsService(ref.watch(dioProvider));
});
