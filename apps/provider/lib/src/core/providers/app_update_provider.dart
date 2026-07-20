import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppUpdateRequirementNotifier extends Notifier<AppUpdateRequirement?> {
  @override
  AppUpdateRequirement? build() => null;

  void requireUpdate(AppUpdateRequirement requirement) {
    final current = state;
    if (current == null ||
        (requirement.minimumBuild ?? 0) >= (current.minimumBuild ?? 0)) {
      state = requirement;
    }
  }
}

final appUpdateRequirementProvider =
    NotifierProvider<AppUpdateRequirementNotifier, AppUpdateRequirement?>(
  AppUpdateRequirementNotifier.new,
);
