import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Manages the provider's online/offline/busy status — shared by both the
/// driver and artisan home screens.
///
/// Toggle is locked when status is [DriverStatus.busy] (active ride/job).
class ProviderStatusNotifier extends StateNotifier<DriverStatus> {
  ProviderStatusNotifier() : super(DriverStatus.offline);

  void goOnline({bool force = false}) {
    if (force || state != DriverStatus.busy) {
      state = DriverStatus.online;
    }
  }

  /// Called when the active job settles — transitions busy → online so the
  /// socket connection is re-established and the artisan can receive new
  /// jobs without having to toggle the online switch manually.
  void resumeAfterJob() {
    state = DriverStatus.online;
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

/// Role-agnostic provider availability state. Shared by driver and artisan
/// home screens; the backend disambiguates via the caller's role on
/// location-update and availability endpoints.
final providerStatusProvider =
    StateNotifierProvider<ProviderStatusNotifier, DriverStatus>(
  (ref) => ProviderStatusNotifier(),
);
