import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';

/// Cap on the number of snapshots kept in memory. Older items are dropped
/// off the tail as new ones arrive via socket so the carousel doesn't grow
/// unbounded over a long session.
const int _kLiveFeedMax = 20;

/// State holder for the artisan home "Live Job Feed" carousel.
///
/// Seeded once via `JobService.getLiveFeed()` on construction, then kept
/// in sync by a `job:feed:new` socket listener (wired in `socket_provider`)
/// that calls [prepend]. The list is newest-first and capped at
/// [_kLiveFeedMax] entries.
class LiveJobFeedNotifier extends StateNotifier<List<LiveFeedJob>> {
  LiveJobFeedNotifier(this._ref) : super(const []) {
    _seed();
  }

  final Ref _ref;

  Future<void> _seed() async {
    try {
      final jobs = await _ref.read(jobServiceProvider).getLiveFeed();
      if (!mounted) return;
      state = jobs.take(_kLiveFeedMax).toList(growable: false);
    } catch (e) {
      debugLog(() => '[LiveJobFeed] seed failed: $e');
      // Keep state as empty list — carousel falls back to placeholder.
    }
  }

  /// Insert a freshly broadcast job at the head of the feed. Idempotent: a
  /// duplicate id (same socket payload re-delivered, or a poll+socket race)
  /// is silently dropped.
  void prepend(LiveFeedJob job) {
    if (state.any((j) => j.id == job.id)) return;
    final next = <LiveFeedJob>[job, ...state];
    state = next.length > _kLiveFeedMax ? next.sublist(0, _kLiveFeedMax) : next;
  }

  /// Pull-to-refresh entry point — re-seeds from REST.
  Future<void> refresh() async {
    await _seed();
  }
}

final liveJobFeedProvider =
    StateNotifierProvider<LiveJobFeedNotifier, List<LiveFeedJob>>(
  (ref) => LiveJobFeedNotifier(ref),
);
