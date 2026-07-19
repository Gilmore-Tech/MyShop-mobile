import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Manages the provider's online/offline/busy status — shared by both the
/// driver and artisan home screens.
///
/// Toggle is locked when status is [DriverStatus.busy] (active ride/job).
class ProviderStatusNotifier extends StateNotifier<DriverStatus> {
  ProviderStatusNotifier() : super(DriverStatus.offline);

  int _transitionRevision = 0;

  /// Monotonic local-intent version used to reject availability snapshots
  /// that started before a newer toggle or active-work transition.
  int get transitionRevision => _transitionRevision;

  void _transitionTo(DriverStatus next) {
    if (state == next) return;
    _transitionRevision += 1;
    state = next;
  }

  void goOnline({bool force = false}) {
    if (force || state != DriverStatus.busy) {
      _transitionTo(DriverStatus.online);
    }
  }

  /// Called when the active job settles — transitions busy → online so the
  /// socket connection is re-established and the artisan can receive new
  /// jobs without having to toggle the online switch manually.
  void resumeAfterJob() {
    _transitionTo(DriverStatus.online);
  }

  /// Leaves the busy state after terminal work. A degraded provider must not
  /// briefly re-enter Online while the backend completion trigger is forcing
  /// the role Offline pending a fresh GPS fix.
  void finishActiveWork({required bool locationRecoveryRequired}) {
    _transitionTo(
      locationRecoveryRequired ? DriverStatus.offline : DriverStatus.online,
    );
  }

  void goOffline() {
    if (state != DriverStatus.busy) {
      _transitionTo(DriverStatus.offline);
    }
  }

  void toggle() {
    if (state == DriverStatus.busy) return;
    _transitionTo(
      state.isOnline ? DriverStatus.offline : DriverStatus.online,
    );
  }

  void setBusy() => _transitionTo(DriverStatus.busy);
}

/// Role-agnostic provider availability state. Shared by driver and artisan
/// home screens; the backend disambiguates via the caller's role on
/// location-update and availability endpoints.
final providerStatusProvider =
    StateNotifierProvider<ProviderStatusNotifier, DriverStatus>(
  (ref) => ProviderStatusNotifier(),
);
