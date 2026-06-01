import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Holds the in-session queue of incoming job requests the artisan has been
/// notified about but not yet acted on (bid / declined / expired).
///
/// Why it exists: the socket-driven incoming-request modal is transient —
/// once dismissed (intentionally or accidentally) the user has nowhere to
/// re-open the request. This list backs the "New" tab on the My Jobs screen
/// so they can return to any pending request.
///
/// Lifecycle:
///   - `enqueue(job)` — appended whenever the socket fires `job:new`.
///   - `remove(jobId)` — called after the artisan submits a bid, declines,
///     or the job is no longer open.
///   - List is in-memory only; it clears on app restart, which is fine
///     because the backend is the source of truth and re-sends pending
///     requests on socket reconnect.
class PendingIncomingJobsNotifier extends StateNotifier<List<Job>> {
  PendingIncomingJobsNotifier() : super(const []);

  /// Add a job to the front of the list (newest first). De-dupes by id.
  void enqueue(Job job) {
    final existing = state.where((j) => j.id != job.id);
    state = [job, ...existing];
  }

  /// Remove a job by id (e.g. after bid submitted or declined).
  void remove(String jobId) {
    state = state.where((j) => j.id != jobId).toList();
  }

  /// Wipe everything (e.g. on logout / role switch).
  void clear() {
    state = const [];
  }
}

final pendingIncomingJobsProvider =
    StateNotifierProvider<PendingIncomingJobsNotifier, List<Job>>(
  (_) => PendingIncomingJobsNotifier(),
);
