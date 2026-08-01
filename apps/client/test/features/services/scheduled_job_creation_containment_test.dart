import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new scheduled artisan jobs stay hidden and omitted for this release',
      () {
    final provider = File(
      'lib/src/features/services/providers/job_form_provider.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/src/features/services/screens/job_form_screen.dart',
    ).readAsStringSync();

    expect(
        provider, contains('const bool kScheduledJobCreationEnabled = false;'));
    expect(
      provider,
      contains('kScheduledJobCreationEnabled && !state.isImmediate'),
    );
    expect(provider, contains(': null,'));
    expect(screen, contains('Scheduling is temporarily unavailable'));
    expect(screen, contains('allowLater: kScheduledJobCreationEnabled'));
  });
}
