import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myshop_provider/src/core/services/directions_service.dart';
import 'package:myshop_provider/src/core/services/nav_guidance.dart';
import 'package:myshop_provider/src/core/widgets/maneuver_banner.dart';

void main() {
  const step = DirectionsStep(
      instruction: 'Turn left',
      maneuver: 'turn-left',
      distanceMeters: 500,
      durationSeconds: 60,
      startLocation: LatLng(0, 0),
      endLocation: LatLng(0, 0.01),
      polyline: []);
  const progress = NavProgress(
      currentStepIndex: 0, distanceToManeuverMeters: 200, currentStep: step);
  for (final phase in ['TO PICKUP', 'TO DESTINATION']) {
    testWidgets('maneuvers keep the live $phase ETA visible', (tester) async {
      Widget banner(int? minutes) => MaterialApp(
          home: Scaffold(
              body: ManeuverBanner(
                  progress: progress,
                  fallbackDistanceMeters: 1000,
                  fallbackEtaMinutes: minutes,
                  fallbackAddress: 'Address',
                  phaseLabel: phase)));
      await tester.pumpWidget(banner(8));
      expect(find.text('Turn left'), findsOneWidget);
      expect(find.text('$phase · 8 min'), findsOneWidget);
      await tester.pumpWidget(banner(5));
      expect(find.text('$phase · 5 min'), findsOneWidget);
      expect(find.text('$phase · 8 min'), findsNothing);
      await tester.pumpWidget(banner(null));
      expect(find.text('$phase · Updating ETA…'), findsOneWidget);
    });
  }
}
