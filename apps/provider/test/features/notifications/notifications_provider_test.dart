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
    expect(
      notification.createdAt,
      DateTime.parse('2026-08-17T08:00:00Z').toLocal(),
    );
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

  test('parses announcement as a first-class inbox type', () {
    final notifications = providerNotificationItemsFromResponse({
      'data': [
        {
          'id': 'announcement_1',
          'channel': 'in_app',
          'type': 'announcement',
          'title': 'Service update',
          'payload': {'destination': 'promotions'},
        },
      ],
    });

    expect(notifications, hasLength(1));
    expect(notifications.single.type, NotifType.announcement);
    expect(notifications.single.eventType, 'announcement');
    expect(notifications.single.payload['destination'], 'promotions');
  });

  test('renders ISO creation timestamps as relative and readable local time',
      () {
    final notification = Notif.fromJson({
      'id': 'notification_time',
      'eventType': 'announcement',
      'title': 'Service update',
      'createdAt': '2026-08-30T19:30:00.000Z',
    });
    final now = DateTime.parse('2026-08-30T21:00:00.000Z');

    expect(
      providerNotificationTimeAgo(notification.createdAt, now: now),
      '1 hour ago',
    );
    expect(
      providerNotificationLocalDateTime(notification.createdAt),
      isNot(contains('T')),
    );
    expect(
      providerNotificationIsToday(notification, now: now),
      isTrue,
    );
  });

  test('groups by local calendar day instead of age-label wording', () {
    final notification = Notif.fromJson({
      'id': 'notification_yesterday',
      'eventType': 'announcement',
      'title': 'Service update',
      'createdAt': '2026-08-29T23:55:00',
    });

    expect(
      providerNotificationIsToday(
        notification,
        now: DateTime.parse('2026-08-30T00:05:00'),
      ),
      isFalse,
    );
    expect(
      providerNotificationTimeAgo(
        notification.createdAt,
        now: DateTime.parse('2026-08-30T00:05:00'),
      ),
      '10 mins ago',
    );
  });

  test('never renders a malformed database timestamp verbatim', () {
    final notification = Notif.fromJson({
      'id': 'notification_bad_time',
      'eventType': 'announcement',
      'title': 'Service update',
      'createdAt': 'raw-db-timestamp',
      'timeAgo': 'Recently',
    });

    expect(notification.createdAt, isNull);
    expect(
      providerNotificationTimeAgo(
        notification.createdAt,
        fallback: notification.fallbackTimeAgo,
      ),
      'Recently',
    );
    expect(providerNotificationLocalDateTime(notification.createdAt), isEmpty);
  });

  test('rejects an ISO timestamp supplied in legacy timeAgo', () {
    final notification = Notif.fromJson({
      'id': 'notification_iso_fallback',
      'eventType': 'announcement',
      'title': 'Service update',
      'timeAgo': '2026-08-30T20:00:00.000Z',
    });

    expect(notification.createdAt, isNull);
    expect(notification.fallbackTimeAgo, isEmpty);
    expect(
      providerNotificationTimeAgo(
        notification.createdAt,
        fallback: notification.fallbackTimeAgo,
      ),
      isEmpty,
    );
  });

  test('rejects raw non-relative values supplied in legacy timeAgo', () {
    for (final raw in ['1788120000000', 'raw-db-timestamp']) {
      final notification = Notif.fromJson({
        'id': 'notification_raw_fallback_$raw',
        'eventType': 'announcement',
        'title': 'Service update',
        'timeAgo': raw,
      });

      expect(notification.fallbackTimeAgo, isEmpty);
    }
  });

  test('notification state starts in loading rather than empty', () {
    const state = ProviderNotifsState.initial();

    expect(state.isLoading, isTrue);
    expect(state.items, isEmpty);
    expect(state.hasLoadError, isFalse);
  });
}
