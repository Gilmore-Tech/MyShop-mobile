import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myshop_provider/src/core/providers/location_degradation_provider.dart';
import 'package:myshop_provider/src/core/widgets/location_degradation_banner.dart';

void main() {
  testWidgets('keeps the active-work no-new-requests warning visible',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationDegradationBanner(
            state: ProviderLocationDegradationState(
              isDegraded: true,
              hasActiveWork: true,
              isOffline: false,
              reasonCode: 'permission_lost',
              degradedAt: DateTime.utc(2026, 7, 18, 12),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Finish your current work'), findsOneWidget);
    expect(find.textContaining('new requests are paused'), findsOneWidget);
  });

  testWidgets('shows support escalation without claiming work was cancelled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationDegradationBanner(
            state: ProviderLocationDegradationState(
              isDegraded: true,
              hasActiveWork: true,
              isOffline: false,
              reasonCode: 'gps_unavailable',
              degradedAt: DateTime.utc(2026, 7, 18, 12),
              escalatedAt: DateTime.utc(2026, 7, 18, 12, 2),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('support has been alerted'), findsOneWidget);
    expect(find.textContaining('current work can continue'), findsOneWidget);
  });
}
