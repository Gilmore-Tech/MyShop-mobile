import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../../core/providers/provider_status_provider.dart';

/// Snapshot of the artisan's currently-active job — populated when the
/// artisan taps "Accept & Start Job" on an accepted bid, cleared when the
/// job completes or is cancelled.
///
/// Keeping this as a single nullable slot (rather than a list) mirrors the
/// product rule that an artisan handles one active job at a time. The
/// value is a [Job] so the active-job screen can read status, client name,
/// location, etc. directly without another fetch.
class ActiveJobState {
  const ActiveJobState({
    this.job,
    this.isUpdating = false,
    this.errorMessage,
  });

  final Job? job;
  final bool isUpdating;
  final String? errorMessage;

  bool get hasJob => job != null;

  ActiveJobState copyWith({
    Job? job,
    bool clearJob = false,
    bool? isUpdating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ActiveJobState(
      job: clearJob ? null : (job ?? this.job),
      isUpdating: isUpdating ?? this.isUpdating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Drives the active-job lifecycle on the artisan side.
///
/// The artisan's flow (matching the backend state machine):
///   confirmed        → (tap "Accept & Start") → artisan_en_route
///   artisan_en_route → (tap "I've Arrived")  → arrived
///   arrived          → (tap "Start Job")     → in_progress
///   in_progress      → (tap "Mark Complete") → artisan_marked_complete
class ActiveJobNotifier extends StateNotifier<ActiveJobState> {
  ActiveJobNotifier(this._ref) : super(const ActiveJobState());

  final Ref _ref;

  /// Seed the active-job slot with a freshly-accepted job. Called from the
  /// bid-accepted banner's "Accept & Start Job" action.
  ///
  /// Also flips the artisan's online toggle to `busy` so
  /// `driverLocationStreamProvider` (which early-returns when offline)
  /// keeps emitting GPS fixes. Without this, an artisan who was offline
  /// when the bid landed would see "— km / —" on the active-job header
  /// and no live distance/ETA.
  void setJob(Job job) {
    state = state.copyWith(job: job, clearError: true);
    try {
      _ref.read(providerStatusProvider.notifier).setBusy();
    } catch (_) {
      // Status provider may not be mounted during tests — safe to ignore.
    }
  }

  /// Clear the slot (job completed or cancelled, user left the flow, etc.).
  /// Also flips the artisan back to `online` so the socket reconnects and
  /// new jobs start flowing again — the `busy` state is owned by this
  /// provider, so clearing the slot owns the cleanup.
  void clear() {
    state = const ActiveJobState();
    try {
      _ref.read(providerStatusProvider.notifier).resumeAfterJob();
    } catch (_) {
      // Provider may not be mounted (tests) — safe to ignore.
    }
  }

  /// Apply a status update pushed from the socket handler. Keeps the
  /// active-job slot in sync with `job:status:changed` events so the
  /// CompletionOverlay flips through artisan_marked_complete →
  /// pending_payment → completed without any action from the artisan.
  ///
  /// When the new status is [JobStatus.completed] the artisan is
  /// automatically returned to `online` — their wait is over, the socket
  /// should wake up again so they can take the next job.
  void applyRemoteStatus(JobStatus next) {
    final job = state.job;
    if (job == null) return;
    if (job.status == next) return;
    state = state.copyWith(job: job.copyWith(status: next));
    if (next == JobStatus.completed) {
      try {
        _ref.read(providerStatusProvider.notifier).resumeAfterJob();
      } catch (_) {}
    }
  }

  /// Confirm receipt of a cash payment. Runs the same PATCH /jobs/:id/confirm
  /// the client would — backend is idempotent and flips the job to
  /// `completed` regardless of who calls it first. The socket event that
  /// follows drives the overlay's success state via [applyRemoteStatus].
  Future<bool> confirmCashReceipt() async {
    final job = state.job;
    if (job == null) return false;
    if (state.isUpdating) return false;
    state = state.copyWith(isUpdating: true, clearError: true);
    try {
      await _ref.read(jobServiceProvider).confirmJobCompletion(job.id);
      // Optimistically flip to completed so the overlay swaps to the
      // success card immediately — the socket event will reconcile.
      state = state.copyWith(
        job: job.copyWith(status: JobStatus.completed),
        isUpdating: false,
      );
      try {
        _ref.read(providerStatusProvider.notifier).resumeAfterJob();
        if (_ref.exists(artisanJobsProvider)) {
          _ref.read(artisanJobsProvider.notifier).silentReload();
        }
      } catch (_) {}
      return true;
    } on ApiException catch (e) {
      developer.log(
        'confirmCashReceipt failed: ${e.errorCode} — ${e.message}',
        name: 'ActiveJob',
        level: 900,
      );
      state = state.copyWith(
        isUpdating: false,
        errorMessage: _friendlyCashError(e),
      );
      return false;
    } catch (e) {
      developer.log(
        'confirmCashReceipt crashed: $e',
        name: 'ActiveJob',
        level: 1000,
      );
      state = state.copyWith(
        isUpdating: false,
        errorMessage: "Couldn't confirm the payment. Please try again.",
      );
      return false;
    }
  }

  String _friendlyCashError(ApiException e) {
    switch (e.errorCode) {
      case 'PAYMENT_NOT_SETTLED':
        return "The client hasn't completed the payment yet.";
      case 'NOT_ASSIGNED_ARTISAN':
        return "Only this job's assigned artisan can confirm receipt.";
      default:
        return e.message;
    }
  }

  /// Advance through the next valid state. Returns `true` if the backend
  /// accepted the transition, `false` otherwise — the caller can then
  /// surface the `errorMessage` from state.
  Future<bool> advance() async {
    final job = state.job;
    if (job == null) return false;
    final next = _nextStatusFor(job.status);
    if (next == null) return false;
    return _transitionTo(next);
  }

  /// Transition to [artisan_en_route] — the first step after acceptance.
  /// Called explicitly so the UI can start this transition even before the
  /// backend has pushed the `confirmed` status event (optimistic).
  Future<bool> startEnRoute() async {
    return _transitionTo(JobStatus.artisanEnRoute);
  }

  Future<bool> _transitionTo(JobStatus next) async {
    final job = state.job;
    if (job == null) return false;
    if (state.isUpdating) return false;
    state = state.copyWith(isUpdating: true, clearError: true);
    try {
      await _ref
          .read(jobServiceProvider)
          .updateJobStatus(job.id, status: next.toJson());
      // Optimistically reflect the new status in-memory so the timeline
      // moves immediately; the backend `job:status` socket event will
      // arrive shortly after and reconcile any drift via a jobs refresh.
      state = state.copyWith(
        job: job.copyWith(status: next),
        isUpdating: false,
      );
      try {
        if (_ref.exists(artisanJobsProvider)) {
          _ref.read(artisanJobsProvider.notifier).silentReload();
        }
      } catch (_) {}
      return true;
    } on ApiException catch (e) {
      developer.log(
        'updateJobStatus failed: ${e.message}',
        name: 'ActiveJob',
        level: 900,
      );
      state = state.copyWith(
        isUpdating: false,
        errorMessage: _friendlyError(e),
      );
      return false;
    } catch (e) {
      developer.log(
        'updateJobStatus crashed: $e',
        name: 'ActiveJob',
        level: 1000,
      );
      state = state.copyWith(
        isUpdating: false,
        errorMessage: 'Could not update the job. Please try again.',
      );
      return false;
    }
  }

  String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'INVALID_STATUS_TRANSITION':
        return "This job can't move to the next step right now.";
      case 'NOT_ASSIGNED_ARTISAN':
        return 'Only the assigned artisan can update this job.';
      default:
        return e.message;
    }
  }
}

/// The valid next-status in the artisan active-work machine, or null if
/// the job is at a terminal-for-artisan state (`artisan_marked_complete`,
/// `completed`, `cancelled`).
JobStatus? _nextStatusFor(JobStatus current) {
  switch (current) {
    case JobStatus.confirmed:
      return JobStatus.artisanEnRoute;
    case JobStatus.artisanEnRoute:
      return JobStatus.arrived;
    case JobStatus.arrived:
      return JobStatus.inProgress;
    case JobStatus.inProgress:
      return JobStatus.artisanMarkedComplete;
    case JobStatus.pendingAdmin:
    case JobStatus.adminAssigned:
    case JobStatus.open:
    case JobStatus.queued:
    case JobStatus.artisanMarkedComplete:
    case JobStatus.pendingPayment:
    case JobStatus.completed:
    case JobStatus.cancelled:
      return null;
  }
}

final activeJobProvider =
    StateNotifierProvider<ActiveJobNotifier, ActiveJobState>(
  (ref) => ActiveJobNotifier(ref),
);
