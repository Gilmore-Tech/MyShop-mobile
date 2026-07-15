import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myshop_provider/src/core/widgets/incoming_request_map_preview.dart';

void main() {
  group('IncomingRequestMapPreview coordinate safety', () {
    test('accepts a valid Ghana coordinate', () {
      expect(
        IncomingRequestMapPreview.isUsableCoordinate(5.6037, -0.1870),
        isTrue,
      );
    });

    test('rejects missing, non-finite, and out-of-range coordinates', () {
      expect(IncomingRequestMapPreview.isUsableCoordinate(0, 0), isFalse);
      expect(
        IncomingRequestMapPreview.isUsableCoordinate(double.nan, -0.1870),
        isFalse,
      );
      expect(
        IncomingRequestMapPreview.isUsableCoordinate(91, -0.1870),
        isFalse,
      );
      expect(
        IncomingRequestMapPreview.isUsableCoordinate(5.6037, 181),
        isFalse,
      );
    });

    test('builds bounds that contain both route endpoints', () {
      const pickup = LatLng(5.6037, -0.1870);
      const destination = LatLng(5.5600, -0.2050);

      final bounds = IncomingRequestMapPreview.boundsFor(
        pickup,
        destination,
      );

      expect(bounds, isNotNull);
      expect(bounds!.southwest.latitude, destination.latitude);
      expect(bounds.southwest.longitude, destination.longitude);
      expect(bounds.northeast.latitude, pickup.latitude);
      expect(bounds.northeast.longitude, pickup.longitude);
    });
  });

  testWidgets('missing coordinates render a neutral fallback without raw data',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: IncomingRequestMapPreview.location(
              latitude: 0,
              longitude: 0,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Map preview unavailable'), findsOneWidget);
    expect(find.byType(GoogleMap), findsNothing);
    expect(find.textContaining('0.0000'), findsNothing);
  });
}
