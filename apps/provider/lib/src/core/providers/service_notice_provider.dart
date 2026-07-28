import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServiceNoticeState {
  const ServiceNoticeState({
    this.issue,
    this.recoveryEpoch = 0,
  });

  final MobileServiceIssue? issue;
  final int recoveryEpoch;
}

class ServiceNoticeNotifier extends Notifier<ServiceNoticeState> {
  @override
  ServiceNoticeState build() => const ServiceNoticeState();

  void report(MobileServiceIssue issue) {
    state = ServiceNoticeState(
      issue: issue,
      recoveryEpoch: state.recoveryEpoch,
    );
  }

  void recovered() {
    if (state.issue == null) return;
    state = ServiceNoticeState(recoveryEpoch: state.recoveryEpoch + 1);
  }
}

final serviceNoticeProvider =
    NotifierProvider<ServiceNoticeNotifier, ServiceNoticeState>(
  ServiceNoticeNotifier.new,
);
