import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bid_list_provider.dart';
import 'job_detail_provider.dart';

/// Coalesces the REST safety-net refreshes shared by the job screen, bid
/// screen, bid sheet and socket recovery paths.
///
/// Riverpod invalidation correctly replaces cached state, but invalidating an
/// already-loading async provider cannot cancel the HTTP request that has
/// already left the device. At scale, nested job/bid surfaces could therefore
/// multiply one slow request. This coordinator joins an initial load and
/// allows at most one explicit refresh per job/resource at a time.
class JobDataRefreshCoordinator {
  JobDataRefreshCoordinator(this._ref);

  final Ref _ref;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  Future<void> refreshJob(String jobId) {
    return _run('job:$jobId', () async {
      final provider = jobDetailProvider(jobId);
      final current = _ref.read(provider);
      if (current.isLoading) {
        await _ref.read(provider.future);
        return;
      }
      final refreshed = _ref.refresh(provider.future);
      await refreshed;
    });
  }

  Future<void> refreshBids(String jobId) {
    return _run('bids:$jobId', () async {
      final provider = bidsForJobProvider(jobId);
      final current = _ref.read(provider);
      if (current.isLoading) {
        await _ref.read(provider.future);
        return;
      }
      final refreshed = _ref.refresh(provider.future);
      await refreshed;
    });
  }

  Future<void> refreshJobAndBids(String jobId) async {
    await Future.wait<void>([
      refreshJob(jobId),
      refreshBids(jobId),
    ]);
  }

  Future<void> _run(String key, Future<void> Function() operation) {
    final running = _inFlight[key];
    if (running != null) return running;

    late final Future<void> next;
    next = Future<void>.sync(operation)
        .catchError((Object error, StackTrace stackTrace) {
      // The AsyncNotifier retains the failure for the visible error state.
      // Poll/socket safety-net callers intentionally fire-and-forget, so do
      // not leak the same failure as an unhandled asynchronous exception.
      debugPrint('[JobDataRefreshCoordinator] $key refresh failed: $error');
    }).whenComplete(() {
      if (identical(_inFlight[key], next)) _inFlight.remove(key);
    });
    _inFlight[key] = next;
    return next;
  }
}

final jobDataRefreshCoordinatorProvider = Provider<JobDataRefreshCoordinator>(
  JobDataRefreshCoordinator.new,
);
