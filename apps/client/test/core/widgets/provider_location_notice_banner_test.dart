import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myshop_client/src/core/providers/provider_location_notice_provider.dart';
import 'package:myshop_client/src/core/widgets/provider_location_notice_banner.dart';

void main() {
  testWidgets('tells the client the booking continues during location loss',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProviderLocationNoticeBanner(
            notice: ProviderLocationNotice(
              bookingId: 'ride-1',
              bookingType: 'ride',
              escalated: false,
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('booking is still continuing'), findsOneWidget);
  });

  testWidgets('shows the durable support escalation state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProviderLocationNoticeBanner(
            notice: ProviderLocationNotice(
              bookingId: 'job-1',
              bookingType: 'job',
              escalated: true,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('support has been alerted'), findsOneWidget);
    expect(find.textContaining('booking is active'), findsOneWidget);
  });
}
