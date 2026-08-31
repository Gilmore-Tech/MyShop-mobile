import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/features/notifications/providers/notifications_provider.dart';

class _MockNotificationService extends Mock implements NotificationService {}

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
    expect(state.unreadCount, 0);
    expect(state.hasLoadError, isFalse);
  });

  test('prefers exact meta unreadTotal with a list-derived legacy fallback',
      () {
    final items = [
      Notif.fromJson({
        'id': 'unread_1',
        'eventType': 'announcement',
        'title': 'Unread',
      }),
      Notif.fromJson({
        'id': 'read_1',
        'eventType': 'announcement',
        'title': 'Read',
        'readAt': '2026-08-30T20:00:00Z',
      }),
    ];

    expect(
      providerNotificationUnreadCountFromResponse(
        {
          'data': const [],
          'meta': {'unreadTotal': 7},
        },
        items: items,
      ),
      7,
    );
    expect(
      providerNotificationUnreadCountFromResponse(
        {'data': const []},
        items: items,
      ),
      1,
    );
  });

  test('tray announcement correlation uses campaignId and ignores route', () {
    final first = Notif.fromJson({
      'id': 'in_app_1',
      'eventType': 'announcement',
      'payload': {
        'campaignId': '11111111-1111-4111-8111-111111111111',
        'route': '/earnings',
      },
    });
    final second = Notif.fromJson({
      'id': 'in_app_2',
      'eventType': 'announcement',
      'payload': {
        'campaignId': '22222222-2222-4222-8222-222222222222',
        'route': '/account',
      },
    });

    final matched = providerNotificationForTrayPayload(
      [first, second],
      {
        'type': 'announcement',
        'campaignId': '22222222-2222-4222-8222-222222222222',
        // A conflicting remote route must have no influence on correlation.
        'route': '/earnings',
      },
    );

    expect(matched?.id, 'in_app_2');
  });

  test(
      'tray lifecycle correlation requires normalized type and valid entity id',
      () {
    final notification = Notif.fromJson({
      'id': 'in_app_bid',
      'eventType': 'job.bid_selected',
      'payload': {
        'jobId': '33333333-3333-4333-8333-333333333333',
      },
    });

    expect(
      providerNotificationForTrayPayload(
        [notification],
        {
          'type': 'bid_accepted',
          'jobId': '33333333-3333-4333-8333-333333333333',
        },
      )?.id,
      'in_app_bid',
    );
    expect(
      providerNotificationForTrayPayload(
        [notification],
        {
          'type': 'ride_settled',
          'jobId': '33333333-3333-4333-8333-333333333333',
          'route': '/notifications',
        },
      ),
      isNull,
    );
    expect(
      providerNotificationForTrayPayload(
        [notification],
        {
          'type': 'bid_accepted',
          'jobId': '../unsafe',
        },
      ),
      isNull,
    );
  });

  test(
      'channel correlation matches verification and location alerts without entity ids',
      () {
    for (final eventType in [
      'verification.rejected',
      'provider.location_degraded',
    ]) {
      final notification = Notif.fromJson({
        'id': 'in_app_$eventType',
        'eventType': eventType,
        'payload': {
          'correlationId': '66666666-6666-4666-8666-666666666666',
          'route': '/untrusted/remote/path',
        },
      });

      expect(
        providerNotificationForTrayPayload(
          [notification],
          {
            'type': eventType,
            'correlationId': '66666666-6666-4666-8666-666666666666',
            'notificationId': 'push-channel-row',
            'route': '/different/untrusted/path',
          },
        )?.id,
        'in_app_$eventType',
      );
    }
  });

  test('notifier uses exact count and decrements correlated reads once',
      () async {
    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30)).thenAnswer(
      (_) async => {
        'data': [
          {
            'id': 'in_app_announcement',
            'channel': 'in_app',
            'eventType': 'announcement',
            'payload': {
              'campaignId': '44444444-4444-4444-8444-444444444444',
            },
          },
          {
            'id': 'in_app_earnings',
            'channel': 'in_app',
            'eventType': 'earnings.updated',
            'payload': {
              'rideId': '55555555-5555-4555-8555-555555555555',
            },
          },
        ],
        'meta': {'unreadTotal': 4},
      },
    );
    when(() => service.markAsRead(any())).thenAnswer((_) async {});
    when(() => service.markAllAsRead()).thenAnswer((_) async {});
    final notifier = NotifsNotifier(service);
    addTearDown(notifier.dispose);
    await notifier.reload();

    expect(notifier.state.unreadCount, 4);
    final payload = <String, dynamic>{
      'type': 'announcement',
      'campaignId': '44444444-4444-4444-8444-444444444444',
      // This is intentionally a push-channel id and must not be PATCHed.
      'notificationId': 'push_sibling_id',
    };
    expect(
      await notifier.markReadForTrayPayload(payload),
      'in_app_announcement',
    );
    expect(notifier.state.unreadCount, 3);

    // Duplicate platform tap callbacks are idempotent locally.
    await notifier.markReadForTrayPayload(payload);
    expect(notifier.state.unreadCount, 3);
    verify(() => service.markAsRead('in_app_announcement')).called(1);
    verifyNever(() => service.markAsRead('push_sibling_id'));

    await notifier.markAllRead();
    expect(notifier.state.unreadCount, 0);
    verify(() => service.markAllAsRead()).called(1);
    verifyNever(() => service.markAsRead('in_app_earnings'));
  });

  test('failed optimistic tray read retries until the server acknowledges it',
      () async {
    final service = _MockNotificationService();
    var failReload = false;
    when(() => service.getNotifications(page: 1, limit: 30)).thenAnswer(
      (_) async {
        if (failReload) throw Exception('offline');
        return {
          'data': [
            {
              'id': 'in_app_verification',
              'channel': 'in_app',
              'eventType': 'verification.rejected',
              'payload': {
                'correlationId': '77777777-7777-4777-8777-777777777777',
              },
            },
          ],
          'meta': {'unreadTotal': 1},
        };
      },
    );
    var attempts = 0;
    when(() => service.markAsRead('in_app_verification')).thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) throw Exception('offline');
    });
    final notifier = NotifsNotifier(service);
    addTearDown(notifier.dispose);
    await notifier.reload();

    final payload = <String, dynamic>{
      'type': 'verification.rejected',
      'correlationId': '77777777-7777-4777-8777-777777777777',
    };
    expect(await notifier.markReadForTrayPayload(payload), isNull);
    expect(notifier.state.items.single.isRead, isTrue);
    expect(notifier.state.unreadCount, 0);

    // A failed refresh must not turn the optimistic read into server proof.
    failReload = true;
    await notifier.reload();
    expect(
        await notifier.markReadForTrayPayload(payload), 'in_app_verification');
    expect(attempts, 2);
  });
}
