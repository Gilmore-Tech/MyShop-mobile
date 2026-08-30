import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/services/local_notification_service.dart';
import 'package:myshop_provider/src/features/notifications/screens/notifications_list_screen.dart';

class _MockNotificationService extends Mock implements NotificationService {}

GoRouter _router({required String initialLocation}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                const Text('Role dashboard'),
                TextButton(
                  onPressed: () => context.push('/notifications'),
                  child: const Text('Open notifications'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const ProviderNotificationsScreen(),
        ),
        GoRoute(
          path: '/earnings',
          builder: (context, state) =>
              const Scaffold(body: Text('Earnings destination')),
        ),
        GoRoute(
          path: '/account/documents',
          builder: (context, state) =>
              const Scaffold(body: Text('Documents destination')),
        ),
        GoRoute(
          path: '/account/vehicle',
          builder: (context, state) =>
              const Scaffold(body: Text('Vehicle destination')),
        ),
      ],
    );

Widget _app(GoRouter router, NotificationService service) => ProviderScope(
      overrides: [apiNotificationServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(routerConfig: router),
    );

void main() {
  testWidgets('shows loading instead of the caught-up empty state initially',
      (tester) async {
    final service = _MockNotificationService();
    final pending = Completer<Map<String, dynamic>>();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) => pending.future);
    final router = _router(initialLocation: '/notifications');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service));
    await tester.pump();

    expect(find.text('Loading notifications…'), findsOneWidget);
    expect(find.text("You're all caught up!"), findsNothing);
  });

  testWidgets('tray inbox Back returns to the active role dashboard',
      (tester) async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => {'data': <Object>[]});
    final router = _router(initialLocation: '/home');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service));
    await tester.pumpAndSettle();
    openProviderSystemTrayDestination(
      destination: providerAnnouncementRoute('notifications'),
      go: router.go,
      push: (route) => unawaited(router.push(route)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Role dashboard'), findsOneWidget);
  });

  testWidgets('in-app announcement item pushes and Back returns to the inbox',
      (tester) async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => {
              'data': [
                {
                  'id': 'announcement_1',
                  'channel': 'in_app',
                  'type': 'announcement',
                  'title': 'Service update',
                  'body': 'See your latest earnings.',
                  'createdAt': '2026-08-30T20:00:00Z',
                  'payload': {'destination': 'promotions'},
                },
              ],
            });
    when(() => service.markAsRead('announcement_1')).thenAnswer((_) async {});
    final router = _router(initialLocation: '/home');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service));
    await tester.tap(find.text('Open notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);

    await tester.tap(find.text('Service update'));
    await tester.pumpAndSettle();
    expect(find.text('Earnings destination'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('safe lifecycle item pushes and Back returns to the inbox',
      (tester) async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => {
              'data': [
                {
                  'id': 'ride_category_1',
                  'channel': 'in_app',
                  'eventType': 'ride_category.approved',
                  'title': 'Ride category approved',
                  'body': 'Your vehicle category is ready.',
                  'createdAt': '2026-08-30T20:00:00Z',
                },
              ],
            });
    when(() => service.markAsRead('ride_category_1')).thenAnswer((_) async {});
    final router = _router(initialLocation: '/home');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service));
    await tester.tap(find.text('Open notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ride category approved'));
    await tester.pumpAndSettle();
    expect(find.text('Vehicle destination'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
  });
}
