import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/notifications/providers/notifications_provider.dart';

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

void main() {
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
}
