import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/chat/shared_prefs_chat_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('logout fence and login B cannot load or replay session A outbox',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final sessionA = SharedPreferencesChatOutbox(
      prefs,
      ownerKey: 'auth-root-A|driver|driver-A|session-A',
    );
    const channel = 'ride:booking-1';
    final pendingA = ChatOutboxItem(
      tempId: 'tmp-A',
      channelKey: channel,
      message: 'message queued by A',
      queuedAt: DateTime.utc(2026, 7, 30, 10),
    );
    await sessionA.upsert(pendingA);

    // An explicit-logout fence publishes no active chat owner. A later login
    // constructs a new exact-session outbox instead of reusing A's queue.
    final sessionB = SharedPreferencesChatOutbox(
      prefs,
      ownerKey: 'auth-root-B|driver|driver-B|session-B',
    );
    expect(await sessionB.readForChannel(channel), isEmpty);

    final pendingB = ChatOutboxItem(
      tempId: 'tmp-B',
      channelKey: channel,
      message: 'message queued by B',
      queuedAt: DateTime.utc(2026, 7, 30, 11),
    );
    await sessionB.upsert(pendingB);

    expect(
      (await sessionA.readForChannel(channel)).map((item) => item.tempId),
      ['tmp-A'],
    );
    expect(
      (await sessionB.readForChannel(channel)).map((item) => item.tempId),
      ['tmp-B'],
    );
  });

  test('fresh login for the same account still gets a new session queue',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final oldSession = SharedPreferencesChatOutbox(
      prefs,
      ownerKey: 'auth-root-A|artisan|artisan-A|session-old',
    );
    await oldSession.upsert(
      ChatOutboxItem(
        tempId: 'tmp-old',
        channelKey: 'job:booking-2',
        message: 'stale send',
        queuedAt: DateTime.utc(2026, 7, 30, 10),
      ),
    );

    final freshSession = SharedPreferencesChatOutbox(
      prefs,
      ownerKey: 'auth-root-A|artisan|artisan-A|session-new',
    );

    expect(await freshSession.readForChannel('job:booking-2'), isEmpty);
  });
}
