import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/notifications/providers/notifications_provider.dart';
import 'package:myshop_client/src/features/notifications/widgets/client_notification_bell.dart';

Widget _appWithUnreadCount(int count) => ProviderScope(
      overrides: [
        clientUnreadNotificationCountProvider.overrideWithValue(count),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ClientNotificationBell(contained: true),
        ),
      ),
    );

void main() {
  testWidgets('bell hides the red dot when no notifications are unread',
      (tester) async {
    await tester.pumpWidget(_appWithUnreadCount(0));

    expect(find.byKey(const Key('client-notification-bell')), findsOneWidget);
    expect(
      find.byKey(const Key('client-notification-unread-dot')),
      findsNothing,
    );
  });

  testWidgets('bell shows the red dot for an exact positive unread total',
      (tester) async {
    await tester.pumpWidget(_appWithUnreadCount(4));

    expect(
      find.byKey(const Key('client-notification-unread-dot')),
      findsOneWidget,
    );
    expect(find.byTooltip('Notifications, 4 unread'), findsOneWidget);
  });
}
