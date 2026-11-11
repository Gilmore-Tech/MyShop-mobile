import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/surge_areas_service.dart';

Color surgeIntensityColor(double multiplier) => Color.lerp(
      const Color(0xFFFF9800),
      const Color(0xFFD32F2F),
      ((multiplier - 1) / 1).clamp(0.0, 1.0),
    )!;

Set<Polygon> surgeHeatmapPolygons(List<SurgeMapArea> areas,
        {void Function(SurgeMapArea)? onTap}) =>
    {
      for (final area in areas)
        for (var i = 0; i < area.polygons.length; i++)
          Polygon(
            polygonId: PolygonId('surge:${area.id}:$i'),
            points: area.polygons[i].outline,
            holes: area.polygons[i].holes,
            fillColor:
                surgeIntensityColor(area.multiplier).withValues(alpha: 0.32),
            strokeColor:
                surgeIntensityColor(area.multiplier).withValues(alpha: 0.65),
            strokeWidth: 1,
            zIndex: 1,
            consumeTapEvents: true,
            onTap: () => onTap?.call(area),
          ),
    };

class SurgeHeatmapLegend extends StatelessWidget {
  const SurgeHeatmapLegend({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Surge',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(height: 5),
                DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFFFF9800), Color(0xFFD32F2F)])),
                    child: SizedBox(width: 90, height: 5)),
                SizedBox(height: 3),
                Text('Lower → Higher', style: TextStyle(fontSize: 10)),
              ],
            )),
      );
}
