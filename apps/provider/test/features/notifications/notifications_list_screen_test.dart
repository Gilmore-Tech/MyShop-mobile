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
import 'package:shared_models/shared_models.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _MockJobService extends Mock implements JobService {}

const _jobId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _jobResponse(String status) => {
      'id': _jobId,
      'status': status,
      'categoryId': 'category-1',
      'description': 'Repair a leaking tap',
      'latitude': 5.60,
      'longitude': -0.18,
      'clientName': 'Ama Mensah',
      'clientPhone': '0200000000',
      'clientPhotoUrl': 'https://example.com/ama.jpg',
    };

Map<String, dynamic> _activeJobNotification() => {
      'data': [
        {
          'id': 'active_job_1',
          'channel': 'in_app',
          'eventType': 'job.stale_24h',
          'title': 'Job needs an update',
          'body': 'Open the job and record its latest progress.',
          'createdAt': '2026-08-30T20:00:00Z',
          'payload': {NotificationPayload.keyJobId: _jobId},
        },
      ],
    };

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
        GoRoute(
          path: '/account/support',
          builder: (context, state) =>
              const Scaffold(body: Text('Support destination')),
        ),
        GoRoute(
          path: '/trips',
          builder: (context, state) =>
              const Scaffold(body: Text('Trips destination')),
        ),
        GoRoute(
          path: '/active-job',
          builder: (context, state) =>
              const Scaffold(body: Text('Active job destination')),
        ),
      ],
    );

Widget _app(
  GoRouter router,
  NotificationService service, {
  JobService? jobService,
}) =>
    ProviderScope(
      overrides: [
        apiNotificationServiceProvider.overrideWithValue(service),
        if (jobService != null)
          jobServiceProvider.overrideWithValue(jobService),
      ],
      child: MaterialApp.router(routerConfig: router),
    );

void main() {
  test('historical CTA admits only genuinely active job statuses', () {
    for (final status in const [
      JobStatus.confirmed,
      JobStatus.artisanEnRoute,
      JobStatus.arrived,
      JobStatus.inProgress,
      JobStatus.artisanMarkedComplete,
    ]) {
      expect(providerInboxJobStatusCanOpenActive(status), isTrue);
    }

    for (final status in const [
      JobStatus.pendingAdmin,
      JobStatus.adminAssigned,
      JobStatus.open,
      JobStatus.queued,
      JobStatus.pendingPayment,
      JobStatus.completed,
      JobStatus.cancelled,
    ]) {
      expect(providerInboxJobStatusCanOpenActive(status), isFalse);
    }
  });

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

  testWidgets('header uses exact unread total beyond the loaded first page',
      (tester) async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => {
              'data': [
                {
                  'id': 'already_read_1',
                  'channel': 'in_app',
                  'eventType': 'announcement',
                  'title': 'Earlier update',
                  'readAt': '2026-08-30T20:00:00Z',
                },
              ],
              'meta': {'unreadTotal': 5},
            });
    final router = _router(initialLocation: '/notifications');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service));
    await tester.pumpAndSettle();

    expect(find.text('5'), findsOneWidget);
    expect(find.byTooltip('Mark all as read'), findsOneWidget);
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
    expect(find.text('View earnings'), findsOneWidget);

    // The row and its visible CTA resolve through the same safe action.
    await tester.tap(find.text('Service update'));
    await tester.pumpAndSettle();
    expect(find.text('Earnings destination'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);

    await tester.tap(find.text('View earnings'));
    await tester.pumpAndSettle();
    expect(find.text('Earnings destination'), findsOneWidget);
  });

  testWidgets('informational lifecycle item marks read without navigating',
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
    expect(find.text('Review vehicle'), findsNothing);
    await tester.tap(find.text('Ride category approved'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    verify(() => service.markAsRead('ride_category_1')).called(1);
  });

  testWidgets('rejected lifecycle item renders its corrective CTA',
      (tester) async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => {
              'data': [
                {
                  'id': 'ride_category_rejected_1',
                  'channel': 'in_app',
                  'eventType': 'ride_category.rejected',
                  'title': 'Ride category needs attention',
                  'body': 'Review your vehicle details.',
                  'createdAt': '2026-08-30T20:00:00Z',
                  'payload': {'route': '/unsafe/admin'},
                },
              ],
            });
    when(() => service.markAsRead('ride_category_rejected_1'))
        .thenAnswer((_) async {});
    final router = _router(initialLocation: '/home');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service));
    await tester.tap(find.text('Open notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Review vehicle'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey(
          'provider-notification-action-ride_category_rejected_1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vehicle destination'), findsOneWidget);
    verify(() => service.markAsRead('ride_category_rejected_1')).called(1);
  });

  testWidgets('manual assignment hydration failure stays safe and explains it',
      (tester) async {
    final service = _MockNotificationService();
    final jobs = _MockJobService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => {
              'data': [
                {
                  'id': 'manual_job_1',
                  'channel': 'in_app',
                  'eventType': 'job.manually_assigned',
                  'title': 'Job assigned to you',
                  'body': 'Review the job and submit a bid.',
                  'createdAt': '2026-08-30T20:00:00Z',
                  'payload': {
                    NotificationPayload.keyJobId: _jobId,
                    'route': '/unsafe/admin',
                  },
                },
              ],
            });
    when(() => service.markAsRead('manual_job_1')).thenAnswer((_) async {});
    when(() => jobs.getJob(_jobId)).thenThrow(Exception('unavailable'));
    final router = _router(initialLocation: '/home');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service, jobService: jobs));
    await tester.tap(find.text('Open notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Review & bid'), findsOneWidget);
    await tester.tap(find.text('Review & bid'));
    await tester.pump();

    expect(
      find.text('This job could not be opened. Refresh and try again.'),
      findsOneWidget,
    );
    expect(find.text('Notifications'), findsOneWidget);
    verify(() => jobs.getJob(_jobId)).called(1);
  });

  testWidgets('active-job CTA opens only after authoritative active hydration',
      (tester) async {
    final service = _MockNotificationService();
    final jobs = _MockJobService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => _activeJobNotification());
    when(() => service.markAsRead('active_job_1')).thenAnswer((_) async {});
    when(() => jobs.getJob(_jobId))
        .thenAnswer((_) async => _jobResponse('in_progress'));
    final router = _router(initialLocation: '/home');
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, service, jobService: jobs));
    await tester.tap(find.text('Open notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open job'));
    await tester.pumpAndSettle();

    expect(find.text('Active job destination'), findsOneWidget);
    expect(find.text('Trips destination'), findsNothing);
    verify(() => jobs.getJob(_jobId)).called(1);
  });

  for (final terminalStatus in const ['completed', 'cancelled']) {
    testWidgets(
        'historical $terminalStatus job CTA goes to history without becoming active',
        (tester) async {
      final service = _MockNotificationService();
      final jobs = _MockJobService();
      when(() => service.getNotifications(page: 1, limit: 30))
          .thenAnswer((_) async => _activeJobNotification());
      when(() => service.markAsRead('active_job_1')).thenAnswer((_) async {});
      when(() => jobs.getJob(_jobId))
          .thenAnswer((_) async => _jobResponse(terminalStatus));
      final router = _router(initialLocation: '/home');
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router, service, jobService: jobs));
      await tester.tap(find.text('Open notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open job'));
      await tester.pumpAndSettle();

      expect(find.text('Trips destination'), findsOneWidget);
      expect(find.text('Active job destination'), findsNothing);
      expect(
        find.text(
          terminalStatus == 'completed'
              ? 'This job is already completed. You can review it in My Jobs.'
              : 'This job was cancelled. You can review it in My Jobs.',
        ),
        findsOneWidget,
      );
      verify(() => jobs.getJob(_jobId)).called(1);
    });
  }
}
