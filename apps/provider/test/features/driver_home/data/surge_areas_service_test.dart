import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myshop_provider/src/features/driver_home/data/surge_areas_service.dart';
import 'package:myshop_provider/src/features/driver_home/widgets/surge_heatmap.dart';

void main() {
  final generated = DateTime.utc(2026, 11, 10, 12);
  const ring = [
    [-1.0, 6.0],
    [-0.99, 6.0],
    [-0.99, 6.01],
    [-1.0, 6.0]
  ];
  const hole = [
    [-0.999, 6.001],
    [-0.998, 6.001],
    [-0.998, 6.002],
    [-0.999, 6.001]
  ];
  Map<String, dynamic> entry(
          String id, String source, double multiplier, Map geometry) =>
      {
        'id': id,
        'source': source,
        'name': id,
        'multiplier': multiplier,
        'expiresAt':
            generated.add(const Duration(seconds: 25)).toIso8601String(),
        'geometry': geometry,
      };
  Map<String, dynamic> snapshot() => {
        'generatedAt': generated.toIso8601String(),
        'areas': [
          entry('auto', 'automatic', 1.2, {
            'type': 'MultiPolygon',
            'coordinates': [
              [ring, hole]
            ]
          }),
          entry('manual', 'manual', 1.8, {
            'type': 'Polygon',
            'coordinates': [hole]
          }),
        ],
      };
  test('preserves exact polygon boundaries, holes and both surge sources', () {
    final areas = parseSurgeAreas(snapshot(), requestedAt: generated);
    expect(areas.map((a) => a.source), ['automatic', 'manual']);
    expect(areas.first.polygons.first.outline.first, const LatLng(6, -1));
    final polygons = surgeHeatmapPolygons(areas);
    expect(polygons, hasLength(2));
    expect(polygons.first.holes.single, hasLength(4));
    expect(polygons.first.fillColor, isNot(polygons.last.fillColor));
    expect(surgeHeatmapPolygons([]), isEmpty);
  });
  test('anchors expiry before network latency and handles client clock offset',
      () {
    final localStart = generated.add(const Duration(hours: 2));
    final areas = parseSurgeAreas(snapshot(), requestedAt: localStart);
    expect(areas.first.expiresAt, localStart.add(const Duration(seconds: 25)));
  });
  test('rejects malformed geographic coverage instead of drawing broad blobs',
      () {
    final json = snapshot();
    (json['areas'] as List).first['geometry'] = {
      'type': 'Point',
      'coordinates': [-1, 6]
    };
    expect(() => parseSurgeAreas(json, requestedAt: generated),
        throwsFormatException);
  });
  test('does not map an unsurcharged area', () {
    final json = snapshot();
    (json['areas'] as List).first['multiplier'] = 1;
    expect(() => parseSurgeAreas(json, requestedAt: generated),
        throwsFormatException);
  });
}
