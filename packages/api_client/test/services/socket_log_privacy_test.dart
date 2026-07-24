import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime transports never log raw payloads or connection ids', () {
    final sources = <String, String>{
      'general':
          File('lib/src/services/socket_service.dart').readAsStringSync(),
      'call': File('lib/src/services/app_call_socket_service.dart')
          .readAsStringSync(),
      'chat': File('lib/src/realtime/chat_realtime.dart').readAsStringSync(),
    };

    for (final entry in sources.entries) {
      expect(
        entry.value,
        isNot(contains(r'→ $data')),
        reason: '${entry.key} socket must not log raw payloads',
      );
      expect(
        entry.value,
        isNot(contains('Connected (id:')),
        reason: '${entry.key} socket must not log connection identifiers',
      );
      expect(
        entry.value,
        isNot(contains(r'callId=$callId')),
        reason: '${entry.key} socket must not log call identifiers',
      );
      expect(
        entry.value,
        isNot(contains(r'Disconnected: $reason')),
        reason: '${entry.key} socket must not log server disconnect text',
      );
    }

    expect(
      sources['chat'],
      isNot(contains(r'Server exception: $data')),
    );
    expect(
      sources['chat'],
      contains('Server exception code=\${_safeDiagnosticCode(code)}'),
    );
    expect(
      sources['chat'],
      isNot(contains(r'$e\n$st')),
      reason: 'chat parser errors must not log payload-derived exceptions',
    );
    expect(
      sources['call'],
      isNot(contains(r'Cannot join "$callId"')),
      reason: 'call diagnostics must not log room identifiers',
    );
  });
}
