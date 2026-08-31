import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_client/src/features/notifications/providers/notifications_provider.dart';
import 'package:myshop_client/src/features/profile/providers/profile_provider.dart';
import 'package:myshop_client/src/features/profile/screens/profile_screen.dart';

class _ProfileAccountNotifier extends AccountScreenNotifier {
  @override
  Future<AccountScreenData> build() async => const AccountScreenData(
        profile: AccountProfile(
          userId: 'client-1',
          displayName: 'Ama Mensah',
          maskedEmail: 'ama***@example.com',
          maskedPhone: '+233 ••• ••• 227',
          isKycVerified: true,
        ),
        unreadNotificationCount: 2,
      );
}

void main() {
  testWidgets('Profile uses the shared exact notification bell',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const Scaffold(body: Text('Notification inbox')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountScreenProvider.overrideWith(_ProfileAccountNotifier.new),
          clientUnreadNotificationCountProvider.overrideWithValue(2),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('client-notification-bell')), findsOneWidget);
    expect(
      find.byKey(const Key('client-notification-unread-dot')),
      findsOneWidget,
    );
    expect(find.byTooltip('Notifications, 2 unread'), findsOneWidget);

    await tester.tap(find.byKey(const Key('client-notification-bell')));
    await tester.pumpAndSettle();
    expect(find.text('Notification inbox'), findsOneWidget);
  });
}
