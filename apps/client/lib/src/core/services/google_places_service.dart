import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:dio/dio.dart';

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
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final PlacePrecision precision;
  final List<String> types;

  const PlaceDetail({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.precision = PlacePrecision.point,
    this.types = const [],
  });

  bool get requiresExactPin => precision == PlacePrecision.area;
}

enum PlacePrecision { point, area }

class ReverseGeocodePlace {
  final String name;
  final String address;

  const ReverseGeocodePlace({required this.name, required this.address});
}

/// Authenticated wrapper around MyShop's server-side Google Places proxy.
/// Google web-service keys never leave the backend; the mobile app only keeps
/// its platform-restricted key for the native Maps SDK.
///
/// [biasLatitude]/[biasLongitude] are passed by the DI provider so suggestions
/// are biased toward the user's current device location when known. They fall
/// back to the pilot-city defaults so search still works before the first
/// GPS fix arrives.
class GooglePlacesService {
  GooglePlacesService({
    required Dio dio,
    double? biasLatitude,
    double? biasLongitude,
  })  : _dio = dio,
        _biasLat = biasLatitude ?? _kumasiLat,
        _biasLng = biasLongitude ?? _kumasiLng;

  final Dio _dio;
  final double _biasLat;
  final double _biasLng;
  static const _requestTimeout = Duration(seconds: 5);

  /// Pilot-city centre — used only when no device fix is available yet.
  static const _kumasiLat = 6.6885;
  static const _kumasiLng = -1.6244;

  String? _sessionToken;

  String _ensureSessionToken() {
    return _sessionToken ??= base64Url
        .encode(List<int>.generate(18, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
  }

  Map<String, dynamic> _responseData(Response<dynamic> response) {
    final envelope = response.data as Map<String, dynamic>;
    return envelope['data'] as Map<String, dynamic>;
  }

  /// Fetch autocomplete suggestions for [query].
  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    if (query.trim().isEmpty) {
      _sessionToken = null;
      return const [];
    }

    try {
      final response = await _post(
        '/location/places/autocomplete',
        data: {
          'input': query,
          'latitude': _biasLat,
          'longitude': _biasLng,
          'sessionToken': _ensureSessionToken(),
        },
      );
      final suggestions =
          _responseData(response)['suggestions'] as List<dynamic>? ?? [];
      return suggestions.map((value) {
        final suggestion = value as Map<String, dynamic>;
        return PlaceSuggestion(
          placeId: suggestion['placeId'] as String,
          mainText: suggestion['mainText'] as String? ?? '',
          secondaryText: suggestion['secondaryText'] as String? ?? '',
          fullText: suggestion['fullText'] as String? ?? '',
        );
      }).toList();
    } catch (e) {
      developer.log('[PLACES] backend autocomplete failed: $e',
          name: 'GooglePlacesService', level: 900);
      return const [];
    }
  }

  /// Fetch lat/lng for a [placeId] via Place Details API.
  Future<PlaceDetail?> getPlaceDetail(String placeId) async {
    final sessionToken = _sessionToken;
    try {
      final response = await _post(
        '/location/places/details',
        data: {
          'placeId': placeId,
          if (sessionToken != null) 'sessionToken': sessionToken,
        },
      );
      final data = _responseData(response);
      return PlaceDetail(
        placeId: data['placeId'] as String? ?? placeId,
        name: data['name'] as String? ??
            (data['address'] as String? ?? '').split(',').first.trim(),
        address: data['address'] as String? ?? '',
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
        precision: data['precision'] == 'area'
            ? PlacePrecision.area
            : PlacePrecision.point,
        types:
            (data['types'] as List?)?.whereType<String>().toList() ?? const [],
      );
    } catch (e) {
      developer.log('[PLACES] backend place details failed: $e',
          name: 'GooglePlacesService', level: 900);
      return null;
    } finally {
      _sessionToken = null;
    }
  }

  /// Reverse-geocode a lat/lng to get the nearest address.
  Future<String?> reverseGeocode(double lat, double lng) async {
    return (await reverseGeocodePlace(lat, lng))?.address;
  }

  /// Reverse-geocode an exact point while keeping a short road/place label
  /// separate from its full address.
  Future<ReverseGeocodePlace?> reverseGeocodePlace(
    double lat,
    double lng,
  ) async {
    try {
      final response = await _post(
        '/location/reverse-geocode',
        data: {
          'latitude': lat,
          'longitude': lng,
        },
      );
      final data = _responseData(response);
      final address = data['address'] as String?;
      if (address == null || address.trim().isEmpty) return null;
      final name = data['name'] as String?;
      return ReverseGeocodePlace(
        name: name == null || name.trim().isEmpty
            ? address.split(',').first.trim()
            : name.trim(),
        address: address,
      );
    } catch (e) {
      developer.log('[PLACES] backend reverse geocoding failed: $e',
          name: 'GooglePlacesService', level: 900);
      return null;
    }
  }

  Future<Response<dynamic>> _post(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final cancelToken = CancelToken();
    final timer = Timer(_requestTimeout, () {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('Location request timed out');
      }
    });
    try {
      return await _dio.post(
        path,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          sendTimeout: _requestTimeout,
          receiveTimeout: _requestTimeout,
        ),
      );
    } finally {
      timer.cancel();
    }
  }
}
