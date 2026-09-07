import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import 'provider_status_provider.dart';

const providerConnectionNoticeDelay = Duration(minutes: 2);

/// A continuous interruption is silent for two minutes. Repeated failures do
/// not restart the grace or produce repeated notices. Only a confirmed fresh
/// location write / ready server snapshot clears it, not a socket connection.
class ProviderConnectionRecoveryController extends StateNotifier<bool> {
  ProviderConnectionRecoveryController({
    this.noticeDelay = providerConnectionNoticeDelay,
  }) : super(false);

  final Duration noticeDelay;
  Timer? _noticeTimer;
  bool _recovering = false;

  void interrupted() {
    if (_recovering) return;
    _recovering = true;
    _noticeTimer = Timer(noticeDelay, () => state = true);
  }

  void recovered() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    _recovering = false;
    state = false;
  }

  void dismissNotice() => state = false;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }
}

final providerConnectionRecoveryProvider =
    StateNotifierProvider<ProviderConnectionRecoveryController, bool>((ref) {
  ref.watch(currentAuthSessionIdentityProvider);
  final controller = ProviderConnectionRecoveryController();
  ref.listen(providerStatusProvider, (_, next) {
    if (next.isOffline) controller.recovered();
  });
  return controller;
});

/// Wakes the REST writer on resume/reconnect even if its retry backoff has not
/// elapsed. Auth scoping prevents events from one login waking another writer.
final providerLocationRecoveryKickProvider = StateProvider<int>((ref) {
  ref.watch(currentAuthSessionIdentityProvider);
  return 0;
});
