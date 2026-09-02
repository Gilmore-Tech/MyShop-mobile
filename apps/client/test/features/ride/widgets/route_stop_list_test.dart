import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/edit_trip_provider.dart';
import 'package:myshop_client/src/features/ride/widgets/route_stop_list.dart';

void main() {
  testWidgets(
    'mid-trip pickup and persisted stops are read-only while destination edits',
    (tester) async {
      final edited = <TripStop>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RouteStopList(
                stops: const [
                  TripStop(
                    id: 'pickup',
                    type: StopType.pickup,
                    address: 'Airport',
                    lat: 5.60,
                    lng: -0.17,
                  ),
                  TripStop(
                    id: 'persisted-stop',
                    type: StopType.intermediate,
                    address: '37 Station',
                    lat: 5.59,
                    lng: -0.18,
                    backendStopId: 'server-stop-1',
                  ),
                  TripStop(
                    id: 'destination',
                    type: StopType.destination,
                    address: 'Osu',
                    lat: 5.55,
                    lng: -0.18,
                  ),
                ],
                onReorder: (_, __) {},
                onRemove: (_) {},
                onEditStop: edited.add,
                onAddStop: () {},
                allowDestinationEditing: true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Airport'));
      await tester.tap(find.text('37 Station'));
      expect(edited, isEmpty);

      await tester.tap(find.text('Osu'));
      expect(edited.map((stop) => stop.id), ['destination']);
    },
  );
}
