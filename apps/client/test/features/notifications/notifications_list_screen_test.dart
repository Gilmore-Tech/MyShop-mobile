import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/services/fcm_service.dart';
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
  // Exercise the production sequence. There is deliberately no artificial
  // frame inserted between go(home) and the tray destination.
  final navigation = openClientTrayDestination(router, '/notifications');
  await tester.pumpAndSettle();
  await navigation;
}

void main() {
  const jobId = '11111111-1111-4111-8111-111111111111';
  const rideId = '22222222-2222-4222-8222-222222222222';

  test('inbox action resolver allows known events and validated ids only', () {
    final supplement = clientInboxActionFor(
      eventType: 'job.supplement_requested',
      payload: const {
        NotificationPayload.keyJobId: jobId,
        'route': '/unsafe/admin',
      },
    );
    expect(supplement?.label, 'Review supplement');
    expect(supplement?.route, '/services/job/$jobId/supplement');

    final rating = clientInboxActionFor(
      eventType: 'rating.prompt',
      payload: const {
        NotificationPayload.keyBookingType: 'ride',
        NotificationPayload.keyBookingId: rideId,
      },
    );
    expect(rating?.kind, ClientInboxActionKind.rating);
    expect(rating?.route, '/ride/$rideId/receipt');

    final message = clientInboxActionFor(
      eventType: 'chat.message',
      payload: const {
        NotificationPayload.keyBookingType: 'job',
        NotificationPayload.keyBookingId: jobId,
      },
    );
    expect(message?.label, 'View message');
    expect(message?.route, '/chat');
    expect(
      message?.extra,
      const {'bookingType': 'artisan_job', 'bookingId': jobId},
    );

    expect(
      clientInboxActionFor(
        eventType: 'ride.driver_arrived',
        payload: const {
          NotificationPayload.keyRideId: '../admin',
          'route': '/unsafe/admin',
        },
      ),
      isNull,
    );
    expect(
      clientInboxActionFor(
        eventType: 'new_message',
        payload: const {
          NotificationPayload.keyBookingType: 'ride',
          NotificationPayload.keyBookingId: 'not-a-booking-id',
        },
      ),
      isNull,
    );
    expect(
      clientInboxActionFor(
        eventType: 'unknown.event',
        payload: const {'route': '/profile/payments'},
      ),
      isNull,
    );

    // These are the exact identifier shapes persisted by the backend today.
    // Neither can safely reconstruct a payment screen or exact activity row.
    expect(
      clientInboxActionFor(
        eventType: 'payment.insufficient_balance',
        payload: const {'paymentId': rideId},
      ),
      isNull,
    );
    expect(
      clientInboxActionFor(
        eventType: 'payment.refund_processed',
        payload: const {'disputeId': jobId},
      ),
      isNull,
    );
  });

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

  testWidgets('non-inbox tray destination Back returns to the dashboard',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));

    // Exercise the production same-turn go-then-push coordinator without the
    // inbox source marker. This proves the dashboard is the real route beneath
    // an ordinary tray destination, not merely an inbox-specific fallback.
    final navigation = openClientTrayDestination(router, '/profile/support');
    await tester.pumpAndSettle();
    await navigation;
    await tester.pumpAndSettle();
    expect(find.text('Support destination'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Client dashboard'), findsOneWidget);
    expect(find.text('Profile origin'), findsNothing);
  });

  testWidgets('root tray inbox system Back falls back to client dashboard',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/notifications');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));
    await tester.pumpAndSettle();

    // This reproduces a cold/deep-linked tray open where the OS restores only
    // the destination route and therefore Navigator has nothing to pop.
    expect(router.canPop(), isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Client dashboard'), findsOneWidget);
  });

  testWidgets('tray marker ignores an unrelated restored back stack',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));

    // A platform resume can restore an old route before delivering the tray
    // callback. The explicit marker must return Home, never that stale route.
    unawaited(router.push('/notifications?source=tray'));
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Client dashboard'), findsOneWidget);
    expect(find.text('Profile origin'), findsNothing);
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

  testWidgets('visible CTA and row tap resolve to the same safe destination',
      (tester) async {
    _usePhoneViewport(tester);
    final router = _testRouter(initialLocation: '/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(_routerApp(router, _StaticNotificationService()));

    router.push('/notifications');
    await tester.pumpAndSettle();
    expect(find.text('Get support'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('client-notification-action-announcement_1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Support destination'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Profile origin'), findsOneWidget);

    unawaited(router.push('/notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support update'));
    await tester.pumpAndSettle();
    expect(find.text('Support destination'), findsOneWidget);
  });
}
