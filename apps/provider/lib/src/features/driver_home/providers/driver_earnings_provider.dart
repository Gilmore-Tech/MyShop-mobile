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
///
/// Re-throws on failure so callers can render an error banner with retry —
/// the previous "swallow and return empty" path made an API outage look
/// identical to "driver hasn't earned yet today", hiding production
/// failures behind a normal-looking dashboard.
final driverEarningsProvider = FutureProvider<DriverEarnings>((ref) async {
  return ref.watch(earningsServiceProvider).getEarningsAggregate();
});

/// Recent payouts (most-recent-first, capped at 50). Same refresh story as
/// [driverEarningsProvider] — invalidated by the completion listener so
/// fresh payouts surface as soon as the backend records them.
final driverPayoutsProvider = FutureProvider<List<DriverPayout>>((ref) async {
  return ref.watch(earningsServiceProvider).getPayouts();
});
