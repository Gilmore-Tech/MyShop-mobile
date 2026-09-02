import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/notifications/providers/notifications_provider.dart';
import 'package:myshop_provider/src/features/notifications/widgets/provider_notification_bell.dart';

Widget _appWithUnreadCount(int count) => ProviderScope(
      overrides: [
        providerUnreadNotificationCountProvider.overrideWithValue(count),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ProviderNotificationBell(contained: true),
        ),
      ),
    );

void main() {
  testWidgets('bell hides the red dot when there are no unread notifications',
      (tester) async {
    await tester.pumpWidget(_appWithUnreadCount(0));

    expect(
      find.byKey(const Key('provider-notification-bell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('provider-notification-unread-dot')),
      findsNothing,
    );
  });

  testWidgets('bell shows the red dot for an exact positive unread count',
      (tester) async {
    await tester.pumpWidget(_appWithUnreadCount(3));

    expect(
      find.byKey(const Key('provider-notification-unread-dot')),
      findsOneWidget,
    );
    expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);
  });
}
