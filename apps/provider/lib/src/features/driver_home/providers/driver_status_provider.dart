import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Manages the driver's online/offline/busy status.
///
/// Toggle is locked when status is [DriverStatus.busy] (active ride).
class DriverStatusNotifier extends StateNotifier<DriverStatus> {
  DriverStatusNotifier() : super(DriverStatus.offline);

  void goOnline() {
    if (state != DriverStatus.busy) {
      state = DriverStatus.online;
    }
  }

  void goOffline() {
    if (state != DriverStatus.busy) {
      state = DriverStatus.offline;
    }
  }

  void toggle() {
    if (state == DriverStatus.busy) return;
    state = state.isOnline ? DriverStatus.offline : DriverStatus.online;
  }

  void setBusy() => state = DriverStatus.busy;
}

final driverStatusProvider =
    StateNotifierProvider<DriverStatusNotifier, DriverStatus>(
  (ref) => DriverStatusNotifier(),
);
