import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/notifications/providers/notifications_provider.dart';

void main() {
  test('parses current data/meta notification response and nested payload', () {
    final notifications = providerNotificationItemsFromResponse({
      'data': [
        {
          'id': 'notification_1',
          'eventType': 'verification.rejected',
          'title': 'Verification needs attention',
          'body': 'Your verification was not approved.',
          'createdAt': '2026-08-17T08:00:00Z',
          'readAt': null,
          'payload': {
            'providerType': 'driver',
            'reason': 'The licence photo is unreadable.',
            'rejectedDocumentIds': ['licence_1'],
            'resubmissionRequired': true,
            'route': '/untrusted/backend/path',
          },
        },
      ],
      'meta': {'page': 1, 'total': 1},
    });

    expect(notifications, hasLength(1));
    final notification = notifications.single;
    expect(notification.id, 'notification_1');
    expect(notification.eventType, 'verification.rejected');
    expect(notification.type, NotifType.system);
    expect(notification.isRead, isFalse);
    expect(notification.reason, 'The licence photo is unreadable.');
    expect(notification.body,
        contains('Reason: The licence photo is unreadable.'));
    expect(notification.payload['resubmissionRequired'], isTrue);
    expect(notification.payload['route'], '/untrusted/backend/path');
  });

  test('parses legacy items, type, string payload, and readAt', () {
    final notifications = providerNotificationItemsFromResponse({
      'items': [
        {
          'id': 'notification_2',
          'type': 'job.bid_accepted',
          'message': 'Your bid was accepted.',
          'readAt': '2026-08-17T09:00:00Z',
          'payload': '{"jobId":"job_1","title":"Bid accepted"}',
        },
      ],
    });

    expect(notifications, hasLength(1));
    expect(notifications.single.eventType, 'job.bid_accepted');
    expect(notifications.single.type, NotifType.job);
    expect(notifications.single.title, 'Bid accepted');
    expect(notifications.single.payload['jobId'], 'job_1');
    expect(notifications.single.isRead, isTrue);
  });

  test('an explicit unread flag wins over a historical readAt value', () {
    final notification = Notif.fromJson({
      'id': 'notification_3',
      'eventType': 'verification.document_reviewed',
      'title': 'Document reviewed',
      'isRead': false,
      'readAt': '2026-08-17T09:00:00Z',
    });

    expect(notification.isRead, isFalse);
  });

  test('keeps only the in-app sibling while accepting legacy channel-less rows',
      () {
    final notifications = providerNotificationItemsFromResponse({
      'data': [
        {
          'id': 'in_app_1',
          'channel': 'in_app',
          'eventType': 'verification.rejected',
          'title': 'Verification rejected',
        },
        {
          'id': 'push_1',
          'channel': 'push',
          'eventType': 'verification.rejected',
          'title': 'Verification rejected',
        },
        {
          'id': 'sms_1',
          'channel': 'sms',
          'eventType': 'verification.rejected',
          'title': 'Verification rejected',
        },
        {
          'id': 'legacy_1',
          'eventType': 'job.bid_accepted',
          'title': 'Legacy notification',
        },
      ],
    });

    expect(notifications.map((notification) => notification.id), [
      'in_app_1',
      'legacy_1',
    ]);
  });
}
