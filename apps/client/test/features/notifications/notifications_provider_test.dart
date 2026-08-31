import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/auth_session_identity_provider.dart';
import 'package:myshop_client/src/features/notifications/providers/notifications_provider.dart';
import 'package:myshop_client/src/features/notifications/services/pending_notification_read_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _MockNotificationService extends Mock implements NotificationService {}

const _identity = AuthSessionIdentity(
  subject: '11111111-1111-4111-8111-111111111111',
  role: 'client',
  roleAccountId: '22222222-2222-4222-8222-222222222222',
  sessionId: 'session-1',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses current data/meta response and announcement payload', () {
    final notifications = clientNotificationItemsFromResponse({
      'data': [
        {
          'id': 'announcement_1',
          'channel': 'in_app',
          'type': 'announcement',
          'title': 'Service update',
          'body': 'A new feature is available.',
          'createdAt': '2026-08-30T09:00:00Z',
          'readAt': null,
          'payload': {
            'destination': 'support',
            'route': '/untrusted/backend/path',
          },
        },
      ],
      'meta': {'page': 1, 'total': 1},
    });

    expect(notifications, hasLength(1));
    final notification = notifications.single;
    expect(notification.id, 'announcement_1');
    expect(notification.type, NotifType.announcement);
    expect(notification.eventType, 'announcement');
    expect(notification.payload['destination'], 'support');
    expect(notification.payload['route'], '/untrusted/backend/path');
    expect(notification.isRead, isFalse);
    expect(notification.createdAt, DateTime.parse('2026-08-30T09:00:00Z'));
    expect(
      clientNotificationTimeAgo(
        notification,
        now: DateTime.parse('2026-08-30T11:05:00Z'),
      ),
      '2 hours ago',
    );
  });

  test('keeps in-app rows and accepts legacy items response', () {
    final notifications = clientNotificationItemsFromResponse({
      'items': [
        {
          'id': 'legacy_1',
          'type': 'ride.completed',
          'message': 'Your ride is complete.',
          'readAt': '2026-08-30T09:00:00Z',
        },
        {
          'id': 'push_1',
          'channel': 'push',
          'type': 'announcement',
          'title': 'Duplicate push sibling',
        },
      ],
    });

    expect(notifications.map((notification) => notification.id), ['legacy_1']);
    expect(notifications.single.type, NotifType.ride);
    expect(notifications.single.isRead, isTrue);
  });

  test('groups by the parsed local calendar date and formats local date/time',
      () {
    final localNow = DateTime(2026, 8, 30, 21, 47);
    final localCreatedAt = DateTime(2026, 8, 30, 19, 42);
    final notification = Notif.fromJson({
      'id': 'same_day',
      'type': 'announcement',
      'createdAt': localCreatedAt.toUtc().toIso8601String(),
    });

    expect(clientNotificationIsToday(notification, now: localNow), isTrue);
    expect(
      clientNotificationTimeAgo(notification, now: localNow),
      '2 hours ago',
    );
    expect(
      clientNotificationLocalDateTime(notification),
      '30 Aug 2026 · 7:42 PM',
    );
  });

  test('never exposes an ISO database timestamp as fallback display text', () {
    final notification = Notif.fromJson({
      'id': 'legacy_timestamp',
      'type': 'system',
      'timeAgo': '2026-08-30T09:00:00.000Z',
    });

    expect(notification.createdAt, isNull);
    expect(clientNotificationTimeAgo(notification), 'Recently');
    expect(clientNotificationLocalDateTime(notification), isNull);
  });

  test('starts in loading state instead of an empty inbox', () {
    final service = _PendingNotificationService();
    final notifier = NotifsNotifier(service);
    addTearDown(notifier.dispose);

    expect(notifier.state.isLoading, isTrue);
    expect(notifier.state.hasValue, isFalse);
  });

  test('prefers exact meta unreadTotal with list-derived legacy fallback', () {
    final items = [
      Notif.fromJson({
        'id': 'unread_1',
        'eventType': 'announcement',
      }),
      Notif.fromJson({
        'id': 'read_1',
        'eventType': 'announcement',
        'readAt': '2026-08-30T20:00:00Z',
      }),
    ];

    expect(
      clientNotificationUnreadCountFromResponse(
        {
          'meta': {'unreadTotal': 8},
        },
        items: items,
      ),
      8,
    );
    expect(
      clientNotificationUnreadCountFromResponse(
        const {},
        items: items,
      ),
      1,
    );
  });

  test('notifier decrements exact reads once and uses server mark-all',
      () async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30)).thenAnswer(
      (_) async => {
        'data': [
          {
            'id': 'in_app_1',
            'channel': 'in_app',
            'eventType': 'announcement',
          },
          {
            'id': 'in_app_2',
            'channel': 'in_app',
            'eventType': 'ride.completed',
          },
        ],
        'meta': {'unreadTotal': 5},
      },
    );
    when(() => service.markAsRead(any())).thenAnswer((_) async {});
    when(() => service.markAllAsRead()).thenAnswer((_) async {});
    final notifier = NotifsNotifier(service);
    addTearDown(notifier.dispose);
    await notifier.reload();

    expect(notifier.unreadCount, 5);
    notifier.markRead('in_app_1');
    await Future<void>.delayed(Duration.zero);
    expect(notifier.unreadCount, 4);
    notifier.markRead('in_app_1');
    expect(notifier.unreadCount, 4);

    await notifier.markAllRead();
    expect(notifier.unreadCount, 0);
    verify(() => service.markAsRead('in_app_1')).called(1);
    verify(() => service.markAllAsRead()).called(1);
    verifyNever(() => service.markAsRead('in_app_2'));
  });

  test('tray correlation prefers sibling correlation and ignores push-row id',
      () {
    final notification = Notif.fromJson({
      'id': 'in_app_ride_alert',
      'channel': 'in_app',
      'eventType': 'ride.cancelled',
      'payload': {
        'correlationId': '33333333-3333-4333-8333-333333333333',
        'route': '/untrusted/backend/path',
      },
    });

    expect(
      clientNotificationForTrayPayload(
        [notification],
        {
          'type': 'ride.cancelled',
          'correlationId': '33333333-3333-4333-8333-333333333333',
          'notificationId': 'push-channel-row-id',
          'route': '/different/untrusted/path',
        },
      )?.id,
      'in_app_ride_alert',
    );
  });

  test('failed optimistic tray read retries until server acknowledgement',
      () async {
    final service = _MockNotificationService();
    var failReload = false;
    when(() => service.getNotifications(page: 1, limit: 30)).thenAnswer(
      (_) async {
        if (failReload) throw Exception('offline');
        return {
          'data': [
            {
              'id': 'in_app_ride_alert',
              'channel': 'in_app',
              'eventType': 'ride.cancelled',
              'payload': {
                'correlationId': '44444444-4444-4444-8444-444444444444',
              },
            },
          ],
          'meta': {'unreadTotal': 1},
        };
      },
    );
    var attempts = 0;
    when(() => service.markAsRead('in_app_ride_alert')).thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) throw Exception('offline');
    });
    final notifier = NotifsNotifier(service);
    addTearDown(notifier.dispose);
    await notifier.reload();
    final payload = <String, dynamic>{
      'type': 'ride.cancelled',
      'correlationId': '44444444-4444-4444-8444-444444444444',
    };

    expect(await notifier.markReadForTrayPayload(payload), isNull);
    expect(notifier.unreadCount, 0);
    failReload = true;
    await notifier.reload();
    expect(
      await notifier.markReadForTrayPayload(payload),
      'in_app_ride_alert',
    );
    expect(attempts, 2);
  });

  test('exact role-session change recreates the inbox cache', () async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30))
        .thenAnswer((_) async => {
              'data': <Object>[],
              'meta': {'unreadTotal': 0}
            });
    final container = ProviderContainer(
      overrides: [
        notificationServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentClientAuthSessionIdentityProvider.notifier).state =
        _identity;
    final subscription = container.listen(
      notifsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(notifsProvider.notifier).reload();

    container.read(currentClientAuthSessionIdentityProvider.notifier).state =
        const AuthSessionIdentity(
      subject: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      role: 'client',
      roleAccountId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      sessionId: 'session-2',
    );
    await container.read(notifsProvider.notifier).reload();

    verify(() => service.getNotifications(page: 1, limit: 30)).called(2);
  });

  test('authenticated inbox consumes a durable cold-start tray receipt',
      () async {
    const store = PendingClientNotificationReadStore();
    await store.save(
      {
        'type': 'announcement',
        'correlationId': '55555555-5555-4555-8555-555555555555',
      },
      owner: _identity,
    );
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30)).thenAnswer(
      (_) async => {
        'data': [
          {
            'id': 'in_app_announcement',
            'channel': 'in_app',
            'eventType': 'announcement',
            'payload': {
              'correlationId': '55555555-5555-4555-8555-555555555555',
            },
          },
        ],
        'meta': {'unreadTotal': 1},
      },
    );
    when(() => service.markAsRead('in_app_announcement'))
        .thenAnswer((_) async {});
    final container = ProviderContainer(
      overrides: [
        notificationServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentClientAuthSessionIdentityProvider.notifier).state =
        _identity;
    final subscription = container.listen(
      notifsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(consumePendingClientNotificationReadProvider)();

    expect(container.read(notifsProvider.notifier).unreadCount, 0);
    verify(() => service.markAsRead('in_app_announcement')).called(1);
    expect(await store.loadFor(_identity), isNull);
  });
}
