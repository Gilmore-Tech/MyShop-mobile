import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider socket diagnostics retain event names but not payloads', () {
    final source =
        File('lib/src/core/providers/socket_provider.dart').readAsStringSync();

    expect(source, contains('lastSocketEventProvider.notifier'));
    expect(source, contains('.state = event;'));
    expect(source, isNot(contains('data.toString()')));
    expect(source, isNot(contains(r'$event: $trimmed')));
    expect(source, isNot(contains(r'${ride.id}')));
    expect(source, isNot(contains(r'${job.id}')));
    expect(source, isNot(contains(r'$e\n$st')));
  });
}
