import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/notifications/providers/notifications_provider.dart';
import 'package:myshop_provider/src/features/notifications/services/pending_notification_read_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockNotificationService extends Mock implements NotificationService {}

const _identity = AuthSessionIdentity(
  subject: '11111111-1111-4111-8111-111111111111',
  role: 'driver',
  roleAccountId: '22222222-2222-4222-8222-222222222222',
  sessionId: 'session-1',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists only sanitized correlation fields across store instances',
      () async {
    const store = PendingProviderNotificationReadStore();
    final saved = await store.save(
      {
        'type': 'verification.rejected',
        'correlationId': '33333333-3333-4333-8333-333333333333',
        'notificationId': 'push-row-id',
        'route': '/untrusted/path',
        'body': 'private notification copy',
      },
      owner: _identity,
    );

    expect(saved, isNotNull);
    final restored =
        await const PendingProviderNotificationReadStore().loadFor(_identity);
    expect(restored?.payload, {
      'type': 'verification.rejected',
      'correlationId': '33333333-3333-4333-8333-333333333333',
    });
    expect(restored?.payload, isNot(contains('notificationId')));
    expect(restored?.payload, isNot(contains('route')));
    expect(restored?.payload, isNot(contains('body')));

    final preferences = await SharedPreferences.getInstance();
    final persisted = preferences
        .getKeys()
        .map(preferences.getString)
        .whereType<String>()
        .join();
    expect(persisted, isNot(contains(_identity.subject)));
    expect(persisted, contains(_identity.roleAccountId));
  });

  test('does not replay a pending read into a different account', () async {
    const store = PendingProviderNotificationReadStore();
    await store.save(
      {
        'type': 'announcement',
        'correlationId': '44444444-4444-4444-8444-444444444444',
      },
      owner: _identity,
    );
    const otherIdentity = AuthSessionIdentity(
      // The private auth root can be shared across role accounts. Scoping is
      // deliberately based on the public role-account id and role instead.
      subject: '11111111-1111-4111-8111-111111111111',
      role: 'driver',
      roleAccountId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      sessionId: 'session-2',
    );

    expect(await store.loadFor(otherIdentity), isNull);
    expect(await store.loadFor(_identity), isNull);
  });

  test('failed acknowledgement remains durable and retries safely', () async {
    const store = PendingProviderNotificationReadStore();
    await store.save(
      {
        'type': 'verification.rejected',
        'correlationId': '66666666-6666-4666-8666-666666666666',
      },
      owner: _identity,
    );

    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30)).thenAnswer(
      (_) async => {
        'data': [
          {
            'id': 'in_app_verification_alert',
            'channel': 'in_app',
            'eventType': 'verification.rejected',
            'payload': {
              'correlationId': '66666666-6666-4666-8666-666666666666',
            },
          },
        ],
        'meta': {'unreadTotal': 1},
      },
    );
    var attempts = 0;
    when(() => service.markAsRead('in_app_verification_alert'))
        .thenAnswer((_) async {
      attempts += 1;
      if (attempts == 1) throw Exception('offline');
    });

    final container = ProviderContainer(
      overrides: [
        apiNotificationServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentAuthSessionIdentityProvider.notifier).state =
        _identity;
    final subscription = container.listen(
      providerNotifsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(consumePendingProviderNotificationReadProvider)();
    expect(await store.loadFor(_identity), isNotNull);

    await container.read(consumePendingProviderNotificationReadProvider)();
    expect(await store.loadFor(_identity), isNull);
    expect(attempts, 2);
  });

  test('authenticated inbox load consumes and clears a cold-start receipt',
      () async {
    const store = PendingProviderNotificationReadStore();
    await store.save(
      {
        'type': 'provider.location_degraded',
        'correlationId': '55555555-5555-4555-8555-555555555555',
      },
      owner: _identity,
    );

    final service = _MockNotificationService();
    when(() => service.getNotifications(page: 1, limit: 30)).thenAnswer(
      (_) async => {
        'data': [
          {
            'id': 'in_app_location_alert',
            'channel': 'in_app',
            'eventType': 'provider.location_degraded',
            'payload': {
              'correlationId': '55555555-5555-4555-8555-555555555555',
            },
          },
        ],
        'meta': {'unreadTotal': 1},
      },
    );
    when(() => service.markAsRead('in_app_location_alert'))
        .thenAnswer((_) async {});

    final container = ProviderContainer(
      overrides: [
        apiNotificationServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentAuthSessionIdentityProvider.notifier).state =
        _identity;
    final subscription = container.listen(
      providerNotifsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(consumePendingProviderNotificationReadProvider)();

    expect(container.read(providerNotifsProvider).unreadCount, 0);
    verify(() => service.markAsRead('in_app_location_alert')).called(1);
    expect(await store.loadFor(_identity), isNull);
  });
}
