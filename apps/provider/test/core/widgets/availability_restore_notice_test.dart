import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myshop_provider/src/core/providers/provider_online_intent.dart';
import 'package:myshop_provider/src/core/widgets/availability_restore_notice.dart';

void main() {
  testWidgets('renders actionable restore failure and can be dismissed',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          availabilityRestoreNoticeProvider.overrideWith(
            (_) => 'We kept you offline. Approve your documents and try again.',
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AvailabilityRestoreNoticeBanner()),
        ),
      ),
    );

    expect(
      find.text(
        'We kept you offline. Approve your documents and try again.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('dismiss-availability-restore-notice')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('availability-restore-notice')),
      findsNothing,
    );
  });
}
