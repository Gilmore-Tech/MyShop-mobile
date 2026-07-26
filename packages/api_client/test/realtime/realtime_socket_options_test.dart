import 'package:api_client/src/realtime/realtime_socket_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime sockets use indefinite exponential reconnect with jitter', () {
    final options = buildRealtimeSocketOptions(
      token: 'private-token',
      auth: const {'offerReceiptVersion': 2},
    );

    expect(options['transports'], ['websocket']);
    expect(options['forceNew'], isTrue);
    expect(options['reconnection'], isNot(false));
    expect(options['reconnectionAttempts'], isNull);
    expect(options['reconnectionDelay'], 1000);
    expect(options['reconnectionDelayMax'], 30000);
    expect(options['randomizationFactor'], 0.5);
    expect(options['timeout'], 15000);
    expect(options['auth'], {
      'token': 'private-token',
      'offerReceiptVersion': 2,
    });
  });
}
