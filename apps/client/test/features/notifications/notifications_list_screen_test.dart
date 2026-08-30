import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/services/local_notification_service.dart';
import 'package:myshop_client/src/features/notifications/screens/notifications_list_screen.dart';

class _PendingNotificationService extends NotificationService {
  _PendingNotificationService() : super(Dio());

  final Completer<Map<String, dynamic>> request = Completer();

  @override
  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 20,
  }) =>
      request.future;
}

class _StaticNotificationService extends NotificationService {
  _StaticNotificationService() : super(Dio());

  @override
  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 20,
  }) async {
    return {
      'data': [
        {
          'id': 'announcement_1',
          'channel': 'in_app',
          'eventType': 'announcement',
          'title': 'Support update',
          'body': 'Open support for more information.',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'payload': {'destination': 'support'},
        },
      ],
    };
  }

  @override
  Future<void> markAsRead(String notificationId) async {}
}

GoRouter _testRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('Client dashboard')),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('Profile origin')),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsListScreen(),
      ),
      GoRoute(
        path: '/profile/support',
        builder: (_, __) => Scaffold(
          appBar: AppBar(title: const Text('Support destination')),
          body: const Text('Support content'),
        ),
      ),
    ],
  );
}

Widget _routerApp(GoRouter router, NotificationService service) {
  return ProviderScope(
    overrides: [notificationServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _openTrayInbox(WidgetTester tester, GoRouter router) async {
  final stack = clientTrayNavigationStack('/notifications');
  router.go(stack.first);
  await tester.pumpAndSettle();
  router.push(stack.last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows loading instead of the empty state during initial fetch',
      (tester) async {
    _usePhoneViewport(tester);
    final service = _PendingNotificationService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: NotificationsListScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text("You're all caught up!"), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tray inbox app-bar Back returns to the client dashboard',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/home');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));
    await _openTrayInbox(tester, router);

    expect(find.text('Notifications'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Client dashboard'), findsOneWidget);
  });

  testWidgets('tray inbox system Back returns to the client dashboard',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/home');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));
    await _openTrayInbox(tester, router);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Client dashboard'), findsOneWidget);
  });

  testWidgets('in-app inbox app-bar Back preserves its profile origin',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));

    router.push('/notifications');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Profile origin'), findsOneWidget);
  });

  testWidgets('inbox item system Back returns to inbox then its prior route',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));

    router.push('/notifications');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support update'));
    await tester.pumpAndSettle();
    expect(find.text('Support destination'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Profile origin'), findsOneWidget);
  });
}
