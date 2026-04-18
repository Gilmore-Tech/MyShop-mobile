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
class GooglePlacesService {
  GooglePlacesService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _baseUrl = 'https://maps.googleapis.com/maps/api/place';

  /// Kumasi, Ghana — bias results towards the Ashanti Region.
  static const _locationBias = '6.6885,-1.6244';
  static const _biasRadius = 50000; // 50 km

  /// Fetch autocomplete suggestions for [query].
  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    if (query.trim().isEmpty) return const [];

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
    } catch (_) {
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
