import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/notifications/services/pending_notification_read_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _identity = AuthSessionIdentity(
  subject: '11111111-1111-4111-8111-111111111111',
  role: 'client',
  roleAccountId: '22222222-2222-4222-8222-222222222222',
  sessionId: 'session-1',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists only sanitized correlation fields and public ownership',
      () async {
    const store = PendingClientNotificationReadStore();
    final saved = await store.save(
      {
        'type': 'ride.cancelled',
        'correlationId': '33333333-3333-4333-8333-333333333333',
        'notificationId': 'push-row-id',
        'route': '/untrusted/path',
        'body': 'private notification copy',
        'amountPesewas': 999999,
      },
      owner: _identity,
    );

    expect(saved, isNotNull);
    final restored =
        await const PendingClientNotificationReadStore().loadFor(_identity);
    expect(restored?.payload, {
      'type': 'ride.cancelled',
      'correlationId': '33333333-3333-4333-8333-333333333333',
    });
    expect(restored?.payload, isNot(contains('notificationId')));
    expect(restored?.payload, isNot(contains('route')));
    expect(restored?.payload, isNot(contains('body')));
    expect(restored?.payload, isNot(contains('amountPesewas')));

    final preferences = await SharedPreferences.getInstance();
    final persisted = preferences
        .getKeys()
        .map(preferences.getString)
        .whereType<String>()
        .join();
    expect(persisted, isNot(contains(_identity.subject)));
    expect(persisted, contains(_identity.roleAccountId));
  });

  test('accepts typed entity fallback but rejects a push-row id alone',
      () async {
    expect(
      sanitizeClientNotificationTrayCorrelation({
        'eventType': 'support.ticket_message',
        'ticketId': '44444444-4444-4444-8444-444444444444',
      }),
      {
        'type': 'support.ticket_message',
        'ticketId': '44444444-4444-4444-8444-444444444444',
      },
    );
    expect(
      sanitizeClientNotificationTrayCorrelation({
        'notificationId': 'push-row-id',
        'type': 'payment.confirmed',
      }),
      isNull,
    );
  });

  test('does not replay a pending read into another client account', () async {
    const store = PendingClientNotificationReadStore();
    await store.save(
      {
        'type': 'announcement',
        'correlationId': '55555555-5555-4555-8555-555555555555',
      },
      owner: _identity,
    );
    const otherIdentity = AuthSessionIdentity(
      subject: '11111111-1111-4111-8111-111111111111',
      role: 'client',
      roleAccountId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      sessionId: 'session-2',
    );

    expect(await store.loadFor(otherIdentity), isNull);
    expect(await store.loadFor(_identity), isNull);
  });

  test('an older acknowledgement cannot clear a newer tray receipt', () async {
    const store = PendingClientNotificationReadStore();
    final older = await store.save(
      {
        'type': 'ride.cancelled',
        'correlationId': '66666666-6666-4666-8666-666666666666',
      },
      owner: _identity,
    );
    await Future<void>.delayed(const Duration(microseconds: 1));
    final newer = await store.save(
      {
        'type': 'job.cancelled',
        'correlationId': '77777777-7777-4777-8777-777777777777',
      },
      owner: _identity,
    );

    await store.clearIfReceipt(older!.receiptId);

    final restored = await store.loadFor(_identity);
    expect(restored?.receiptId, newer?.receiptId);
    expect(restored?.payload['correlationId'],
        '77777777-7777-4777-8777-777777777777');
  });

  test('rejects a non-client session identity', () async {
    const providerIdentity = AuthSessionIdentity(
      subject: '11111111-1111-4111-8111-111111111111',
      role: 'driver',
      roleAccountId: '88888888-8888-4888-8888-888888888888',
      sessionId: 'session-3',
    );

    expect(
      await const PendingClientNotificationReadStore().save(
        {
          'type': 'announcement',
          'correlationId': '99999999-9999-4999-8999-999999999999',
        },
        owner: providerIdentity,
      ),
      isNull,
    );
  });
}
