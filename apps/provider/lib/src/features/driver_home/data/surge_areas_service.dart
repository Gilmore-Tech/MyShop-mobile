import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SurgeMapPolygon {
  const SurgeMapPolygon(this.outline, this.holes);
  final List<LatLng> outline;
  final List<List<LatLng>> holes;
}

class SurgeMapArea {
  const SurgeMapArea(
      {required this.id,
      required this.name,
      required this.multiplier,
      required this.source,
      required this.expiresAt,
      required this.polygons});
  final String id;
  final String name;
  final double multiplier;
  final String source;
  final DateTime expiresAt;
  final List<SurgeMapPolygon> polygons;
}

/// Pricing boundaries, not synthetic density dots. GeoJSON holes preserve
/// lower-intensity regions around stronger areas without painting overlaps.
List<SurgeMapArea> parseSurgeAreas(Map<String, dynamic> json,
    {required DateTime requestedAt}) {
  final generatedAt = DateTime.parse(json['generatedAt'] as String);
  final entries = json['areas'] as List;
  return entries.map((value) {
    final area = Map<String, dynamic>.from(value as Map);
    final multiplier = (area['multiplier'] as num).toDouble();
    if (!multiplier.isFinite || multiplier <= 1) {
      throw const FormatException('Invalid surge multiplier');
    }
    final geometry = Map<String, dynamic>.from(area['geometry'] as Map);
    final coordinates = geometry['coordinates'] as List;
    final List polygons;
    switch (geometry['type']) {
      case 'Polygon':
        polygons = [coordinates];
      case 'MultiPolygon':
        polygons = coordinates;
      default:
        throw const FormatException('Unsupported surge geometry');
    }
    List<LatLng> ring(dynamic value) {
      final points = (value as List).map((pair) {
        final coordinate = pair as List;
        final lng = (coordinate[0] as num).toDouble();
        final lat = (coordinate[1] as num).toDouble();
        if (!lat.isFinite ||
            !lng.isFinite ||
            lat.abs() > 90 ||
            lng.abs() > 180) {
          throw const FormatException('Invalid surge coordinates');
        }
        return LatLng(lat, lng);
      }).toList();
      if (points.length < 4 || points.first != points.last) {
        throw const FormatException('Invalid surge boundary');
      }
      return List.unmodifiable(points);
    }

    final serverExpiry = DateTime.parse(area['expiresAt'] as String);
    // Anchor to request start, not receipt, so network delay cannot extend
    // expired authority. Cap the TTL even if an old backend sends a long one.
    final ttlMs =
        serverExpiry.difference(generatedAt).inMilliseconds.clamp(0, 25000);
    return SurgeMapArea(
      id: area['id'] as String,
      name: area['name'] as String,
      multiplier: multiplier,
      source: area['source'] as String,
      expiresAt: requestedAt.add(Duration(milliseconds: ttlMs)),
      polygons: polygons.map((part) {
        final rings = part as List;
        return SurgeMapPolygon(
            ring(rings.first), rings.skip(1).map(ring).toList(growable: false));
      }).toList(growable: false),
    );
  }).toList(growable: false);
}

class SurgeAreasService {
  SurgeAreasService(this._dio);
  final Dio _dio;

  Future<List<SurgeMapArea>> fetch() async {
    final startedAt = DateTime.now();
    final response = await _dio.get<Map<String, dynamic>>('/surge/areas',
        options: Options(
            receiveTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 8)));
    final body = response.data!;
    final data = body['success'] == true ? body['data'] as Map : body;
    return parseSurgeAreas(Map<String, dynamic>.from(data),
        requestedAt: startedAt);
  }
}
