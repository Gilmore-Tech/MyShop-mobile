import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../data/earnings_service.dart';

/// Provides [EarningsService] backed by the app's Dio client.
final earningsServiceProvider = Provider<EarningsService>((ref) {
  return EarningsService(ref.watch(dioProvider));
});

/// Driver earnings (today + week aggregate). Drives both the home-screen
/// summary card and the earnings dashboard. Refresh is triggered by:
///   - the screen mounting (FutureProvider builds once)
///   - `ride:state` snapshots flipping to `completed` (the driver socket
///     listener invalidates this provider so the next `ref.watch` rebuilds
///     and re-fetches both periods)
///   - manual `ref.invalidate(driverEarningsProvider)` (pull-to-refresh).
final driverEarningsProvider = FutureProvider<DriverEarnings>((ref) async {
  try {
    return await ref.watch(earningsServiceProvider).getEarningsAggregate();
  } catch (_) {
    return DriverEarnings.empty;
  }
});

/// Recent payouts (most-recent-first, capped at 50). Same refresh story as
/// [driverEarningsProvider] — invalidated by the completion listener so
/// fresh payouts surface as soon as the backend records them.
final driverPayoutsProvider = FutureProvider<List<DriverPayout>>((ref) async {
  return ref.watch(earningsServiceProvider).getPayouts();
});
