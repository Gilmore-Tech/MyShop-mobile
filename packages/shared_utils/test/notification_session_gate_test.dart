import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  test('holds an intent until an authenticated session is available', () async {
    var probes = 0;
    final session = await waitForNotificationSession<String>(
      probe: () {
        probes += 1;
        return probes == 1
            ? const NotificationSessionSnapshot.restoring()
            : const NotificationSessionSnapshot.authenticated('session-1');
      },
      pollInterval: Duration.zero,
    );

    expect(session, 'session-1');
    expect(probes, 2);
  });

  test('drops an intent when restoration resolves without a session', () async {
    final session = await waitForNotificationSession<String>(
      probe: () => const NotificationSessionSnapshot.unavailable(),
    );

    expect(session, isNull);
  });

  test('bounds an indefinitely restoring session', () async {
    final session = await waitForNotificationSession<String>(
      probe: () => const NotificationSessionSnapshot.restoring(),
      timeout: Duration.zero,
      pollInterval: Duration.zero,
    );

    expect(session, isNull);
  });
}
