import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/widgets/ride_route_map.dart';

void main() {
  Widget buildOverlay({VoidCallback? onChangeDropoff}) {
    return MaterialApp(
      home: Scaffold(
        body: RideDestinationOverlay(
          destination: 'Accra Mall',
          onChangeDropoff: onChangeDropoff,
        ),
      ),
    );
  }

  testWidgets('hides destination editing before an in-progress trip',
      (tester) async {
    await tester.pumpWidget(buildOverlay());

    expect(find.text('HEADING TO'), findsOneWidget);
    expect(find.text('Accra Mall'), findsOneWidget);
    expect(find.text('Change drop-off'), findsNothing);
  });

  testWidgets('offers a direct change drop-off action while in progress',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      buildOverlay(onChangeDropoff: () => tapped = true),
    );

    expect(find.text('Change drop-off'), findsOneWidget);
    await tester.tap(find.byKey(const Key('map-change-dropoff-card')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
