import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../constants/maps_config.dart';

/// A place suggestion returned by Google Places Autocomplete.
class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
  });
}

/// Resolved place with coordinates.
class PlaceDetail {
  final String placeId;
  final String address;
  final double latitude;
  final double longitude;

  const PlaceDetail({
    required this.placeId,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// Lightweight wrapper around Google Places API (legacy) for autocomplete
/// and place detail lookups. Uses the client app's Maps API key.
///
/// [biasLatitude]/[biasLongitude] are passed by the DI provider so suggestions
/// are biased toward the user's current device location when known. They fall
/// back to the pilot-city defaults so search still works before the first
/// GPS fix arrives.
class GooglePlacesService {
  GooglePlacesService({
    Dio? dio,
    double? biasLatitude,
    double? biasLongitude,
  })  : _dio = dio ?? Dio(),
        _biasLat = biasLatitude ?? _kumasiLat,
        _biasLng = biasLongitude ?? _kumasiLng;

  final Dio _dio;
  final double _biasLat;
  final double _biasLng;

  static const _baseUrl = 'https://maps.googleapis.com/maps/api/place';

  /// Pilot-city centre — used only when no device fix is available yet.
  static const _kumasiLat = 6.6885;
  static const _kumasiLng = -1.6244;
  static const _biasRadius = 50000; // 50 km

  String get _locationBias => '$_biasLat,$_biasLng';

  /// Fetch autocomplete suggestions for [query].
  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    if (query.trim().isEmpty) return const [];
    if (MapsConfig.apiKey.isEmpty) {
      // The v1.0 secret cleanup made the default value empty so a build
      // that forgot the dart-define fails visibly instead of silently
      // shipping a placeholder key. Without this log the only visible
      // symptom is "no suggestions appear when typing" because the catch
      // block below swallows the resulting REQUEST_DENIED.
      developer.log(
          '[PLACES] GOOGLE_MAPS_API_KEY is empty — autocomplete will return []. '
          'Re-run with --dart-define=GOOGLE_MAPS_API_KEY=AIza…',
          name: 'GooglePlacesService',
          level: 1000);
      return const [];
    }

    try {
      final response = await _dio.get(
        '$_baseUrl/autocomplete/json',
        queryParameters: {
          'input': query,
          'key': MapsConfig.apiKey,
          'location': _locationBias,
          'radius': _biasRadius,
          'components': 'country:gh',
          'language': 'en',
        },
      );

      final data = response.data as Map<String, dynamic>;
      // Surface Google's own error envelope — `REQUEST_DENIED` /
      // `INVALID_REQUEST` / `OVER_QUERY_LIMIT` arrive with HTTP 200 but
      // a non-OK `status` field, which the old try/catch couldn't see.
      final status = data['status'] as String?;
      if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
        developer.log(
            '[PLACES] autocomplete non-OK status: $status — '
            '${data['error_message'] ?? '(no message)'}',
            name: 'GooglePlacesService',
            level: 900);
        return const [];
      }
      final predictions = data['predictions'] as List<dynamic>? ?? [];

      return predictions.map((p) {
        final structured = p['structured_formatting'] as Map<String, dynamic>?;
        return PlaceSuggestion(
          placeId: p['place_id'] as String,
          mainText: structured?['main_text'] as String? ?? '',
          secondaryText: structured?['secondary_text'] as String? ?? '',
          fullText: p['description'] as String? ?? '',
        );
      }).toList();
    } catch (e) {
      developer.log('[PLACES] autocomplete failed: $e',
          name: 'GooglePlacesService', level: 900);
      return const [];
    }
  }

  /// Fetch lat/lng for a [placeId] via Place Details API.
  Future<PlaceDetail?> getPlaceDetail(String placeId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/details/json',
        queryParameters: {
          'place_id': placeId,
          'key': MapsConfig.apiKey,
          'fields': 'geometry,formatted_address',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      if (location == null) return null;

      return PlaceDetail(
        placeId: placeId,
        address: result['formatted_address'] as String? ?? '',
        latitude: (location['lat'] as num).toDouble(),
        longitude: (location['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocode a lat/lng to get the nearest address.
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '$lat,$lng',
          'key': MapsConfig.apiKey,
          'language': 'en',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;

      return results[0]['formatted_address'] as String?;
    } catch (_) {
      return null;
    }
  }
}
