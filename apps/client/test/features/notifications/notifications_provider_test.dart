import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/notifications/providers/notifications_provider.dart';

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
}
