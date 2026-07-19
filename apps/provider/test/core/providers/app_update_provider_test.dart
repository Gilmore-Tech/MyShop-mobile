import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/app_update_provider.dart';

void main() {
  test('mandatory update state latches and cannot be downgraded', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(appUpdateRequirementProvider.notifier);

    expect(container.read(appUpdateRequirementProvider), isNull);

    notifier.requireUpdate(
      const AppUpdateRequirement(
        message: 'Build 22 required.',
        minimumBuild: 22,
      ),
    );
    notifier.requireUpdate(
      const AppUpdateRequirement(
        message: 'Stale build 21 response.',
        minimumBuild: 21,
      ),
    );

    expect(
      container.read(appUpdateRequirementProvider)?.message,
      'Build 22 required.',
    );
  });
}
