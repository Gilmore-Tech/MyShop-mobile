import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';

void main() {
  test('finishing active work preserves the provider Online choice', () {
    final notifier = ProviderStatusNotifier()..setBusy();

    notifier.finishActiveWork();

    expect(notifier.state, DriverStatus.online);
    notifier.dispose();
  });
}
