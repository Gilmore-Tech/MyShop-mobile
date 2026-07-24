import 'dart:async';
import 'package:api_client/mobile_diagnostics.dart' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../../core/providers/location_degradation_provider.dart';
import '../../../core/providers/availability_reconciliation_controller.dart';
import '../../auth/providers/auth_controller.dart';
import '../../earnings/providers/earnings_providers.dart';
import '../../earnings/providers/ratings_provider.dart';
import '../../../core/services/lifecycle_location_service.dart';

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
  Future<Job?>? _refreshInFlight;

  /// Seed the active-job slot with a freshly-accepted job. Called from the
  /// bid-accepted banner's "Accept & Start Job" action.
  ///
  /// Also flips the artisan's online toggle to `busy` so
  /// `driverLocationStreamProvider` (which early-returns when offline)
  /// keeps emitting GPS fixes. Without this, an artisan who was offline
  /// when the bid landed would see "— km / —" on the active-job header
  /// and no live distance/ETA.
  ///
  /// When the seeded [job] is missing client identity fields (the lean
  /// `GET /jobs` feed shape), kicks off a fire-and-forget
  /// `GET /jobs/:id` to hydrate them so the active-job header and chat
  /// don't show "Client" + generic avatar.
  void setJob(Job job) {
    state = state.copyWith(job: job, clearError: true);
    try {
      _ref.read(providerStatusProvider.notifier).setBusy();
    } catch (_) {
      // Status provider may not be mounted during tests — safe to ignore.
    }
    if (job.clientName == null ||
        job.clientPhotoUrl == null ||
        job.clientPhone == null ||
        job.clientPhone!.trim().isEmpty) {
      _hydrateClientInfo(job.id);
    }
  }

  /// Fetch the full job and merge client identity fields into the active
  /// slot. Non-fatal: a failed fetch leaves the slot as-is.
  Future<void> _hydrateClientInfo(String jobId) async {
    try {
      final raw = await _ref.read(jobServiceProvider).getJob(jobId);
      final fresh = Job.fromJson(raw);
      final current = state.job;
      // Bail if the slot was cleared or swapped while we were in flight.
      if (current == null || current.id != jobId) return;
      state = state.copyWith(
        job: current.copyWith(
          clientName: current.clientName ?? fresh.clientName,
          clientPhone: current.clientPhone ?? fresh.clientPhone,
          clientPhotoUrl: current.clientPhotoUrl ?? fresh.clientPhotoUrl,
          categoryName: current.categoryName ?? fresh.categoryName,
          addressText: current.addressText ?? fresh.addressText,
        ),
      );
    } catch (e) {
      developer.debugLog(
        () => 'Active job client hydration failed for $jobId: $e',
        name: 'ActiveJob',
        level: 800,
      );
    }
  }

  /// Clear the slot (job completed or cancelled, user left the flow, etc.).
  /// Also flips the artisan back to `online` so the socket reconnects and
  /// new jobs start flowing again — the `busy` state is owned by this
  /// provider, so clearing the slot owns the cleanup.
  void clear() {
    state = const ActiveJobState();
    try {
      _finishActiveWork();
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
        _finishActiveWork();
      } catch (_) {}
      // Bust the earnings caches so the dashboard, today-card, performance
      // chart, detailed report, and payouts list all refetch with the
      // newly-completed job factored in. Without this, `FutureProvider`s
      // hold the stale pre-completion snapshot until the screen is
      // recreated or the user pulls to refresh.
      _bustEarningsCaches();
      _refreshUserProfile();
    }
  }

  /// Apply a `job:client_payment_acknowledged` socket event to the active
  /// slot. Fired by the backend when the client opens the payment screen
  /// and picks a method — flips the artisan's "Yes, I received payment"
  /// CTA from disabled (waiting copy) to enabled.
  void applyClientPaymentAck({
    required String jobId,
    required String paymentMethod,
    required String acknowledgedAt,
  }) {
    final job = state.job;
    if (job == null) return;
    if (job.id != jobId) return;
    if (job.clientPaymentAcknowledgedAt == acknowledgedAt &&
        job.clientPaymentMethod == paymentMethod) {
      return;
    }
    state = state.copyWith(
      job: job.copyWith(
        clientPaymentAcknowledgedAt: acknowledgedAt,
        clientPaymentMethod: paymentMethod,
      ),
    );
  }

  /// Pull the latest job from REST and merge payment-acknowledgement
  /// fields into the active slot. Used as a safety net when a socket event
  /// is missed:
  ///   - `artisan-confirm-cash` 409s with `CLIENT_PAYMENT_NOT_ACKNOWLEDGED`
  ///     (client may have just acknowledged but the event hasn't landed),
  ///   - the screen sits in `pending_payment` waiting on the Paystack
  ///     webhook → `completed` event, which battery saver / OS socket
  ///     reaping can swallow silently. The poll closes that gap.
  ///
  /// Status changes are routed through [applyRemoteStatus] so the same
  /// side effects (earnings cache bust, online resume, profile refresh)
  /// fire whether the transition came from the socket or this poll —
  /// without that, a poll-detected `completed` would leave the dashboard
  /// staring at stale earnings.
  Future<Job?> refreshFromServer() {
    final running = _refreshInFlight;
    if (running != null) return running;

    late final Future<Job?> operation;
    operation = _refreshFromServer().whenComplete(() {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    });
    _refreshInFlight = operation;
    return operation;
  }

  Future<Job?> _refreshFromServer() async {
    final job = state.job;
    if (job == null) return null;
    try {
      final raw = await _ref.read(jobServiceProvider).getJob(job.id);
      final fresh = Job.fromJson(raw);
      final current = state.job;
      if (current == null || current.id != job.id) return fresh;
      state = state.copyWith(
        job: current.copyWith(
          // Prefer the backend-authoritative job timestamps once they're
          // present — this lets the local "stamp on tap" fallback in
          // [_transitionTo] get reconciled to the real value the next
          // time we hit the server.
          startedAt: fresh.startedAt ?? current.startedAt,
          completedAt: fresh.completedAt ?? current.completedAt,
          clientPaymentAcknowledgedAt: fresh.clientPaymentAcknowledgedAt,
          clientPaymentMethod: fresh.clientPaymentMethod,
        ),
      );
      // Apply status via the shared path so [applyRemoteStatus]'s
      // side effects (earnings cache bust, online resume, profile refresh
      // when landing as `completed`) run even when the poll — not the
      // socket — caught the transition.
      applyRemoteStatus(fresh.status);
      return fresh;
    } catch (e) {
      developer.debugLog(
        () => 'refreshFromServer failed: $e',
        name: 'ActiveJob',
        level: 800,
      );
      return null;
    }
  }

  /// Confirm receipt of a cash payment. Calls
  /// `POST /jobs/:id/artisan-confirm-cash` — the dedicated artisan-side
  /// endpoint that runs the same finalisation path as a Paystack webhook
  /// (cash payment row, commission split, earnings cache bust, socket
  /// emit, push notifications). Idempotent: a completed job returns 200
  /// without re-writing.
  Future<bool> confirmCashReceipt() async {
    final job = state.job;
    if (job == null) return false;
    if (state.isUpdating) return false;
    state = state.copyWith(isUpdating: true, clearError: true);
    bool success = false;
    try {
      final raw =
          await _ref.read(jobServiceProvider).artisanConfirmCash(job.id);
      var fresh = _safeParseJob(raw);
      if (fresh == null ||
          fresh.id != job.id ||
          fresh.status != JobStatus.completed) {
        developer.debugLog(
          () =>
              'Cash confirmation response was not authoritative for ${job.id}; '
              'reading the job back before showing completion',
          name: 'ActiveJob',
          level: 900,
        );
        fresh = await refreshFromServer();
      }
      if (fresh == null ||
          fresh.id != job.id ||
          fresh.status != JobStatus.completed) {
        state = state.copyWith(
          errorMessage:
              "We couldn't confirm the payment completion. Keep this job open while we check again.",
        );
        return false;
      }
      state = state.copyWith(job: fresh);
      success = true;
      try {
        _finishActiveWork();
        if (_ref.exists(artisanJobsProvider)) {
          _ref.read(artisanJobsProvider.notifier).silentReload();
        }
        // Same reason as in applyRemoteStatus: the cash-confirm endpoint
        // inserted a payment row and split the commission server-side, so
        // every earnings provider needs a fresh fetch on next view.
        _bustEarningsCaches();
        _refreshUserProfile();
      } catch (_) {}
    } on ApiException catch (e) {
      developer.debugLog(
        () => 'confirmCashReceipt failed: status=${e.statusCode} '
            'code=${e.errorCode} — ${e.message}',
        name: 'ActiveJob',
        level: 900,
      );
      state = state.copyWith(errorMessage: _friendlyCashError(e));
      // If the backend says the client hasn't acknowledged yet, the socket
      // event may simply have been missed (battery saver, dropped WS).
      // Pull the job once so the CTA enables the moment the client has
      // actually acknowledged on their side.
      if (e.errorCode == 'CLIENT_PAYMENT_NOT_ACKNOWLEDGED') {
        unawaited(refreshFromServer());
      }
    } catch (e, st) {
      developer.debugLog(
        () => 'confirmCashReceipt crashed: $e\n$st',
        name: 'ActiveJob',
        level: 1000,
      );
      state = state.copyWith(
        errorMessage: "Couldn't confirm the payment. Please try again.",
      );
    } finally {
      // Guarantee the spinner clears no matter which branch fired.
      state = state.copyWith(isUpdating: false);
    }
    return success;
  }

  void _finishActiveWork() {
    final locationRecoveryRequired =
        _ref.read(providerLocationDegradationProvider).isDegraded;
    _ref.read(providerStatusProvider.notifier).finishActiveWork(
          locationRecoveryRequired: locationRecoveryRequired,
        );
    unawaited(
      _ref
          .read(availabilityReconciliationControllerProvider)
          .reconcile(trigger: 'artisan_work_finished'),
    );
  }

  /// Maps the backend's structured error codes for
  /// `POST /jobs/:id/artisan-confirm-cash` into messages the artisan can
  /// act on. Codes match docs/architecture.md.
  /// Invalidates every earnings-flavoured cache so the next read returns
  /// fresh server data. Called whenever a job lands as `completed` (cash
  /// confirm or webhook), since the backend's completion path inserts a
  /// payment row, runs the commission split, and bumps the artisan's
  /// daily/weekly totals — all of which the cached `FutureProvider`s on
  /// the dashboard, performance chart, and detailed report would
  /// otherwise miss.
  void _bustEarningsCaches() {
    try {
      _ref.invalidate(earningsSummaryProvider);
      _ref.invalidate(earningsReportProvider);
      _ref.invalidate(todayCardProvider);
      _ref.invalidate(activeTodayCardProvider);
      _ref.invalidate(payoutsProvider);
      // Rating average rolls forward only when both sides have submitted
      // (blind 24h window) — but the count still bumps the moment a new
      // rating lands, and the home-screen Performance Summary surfaces
      // that count. Without this invalidate the tile stayed frozen at
      // "0 reviews" until app relaunch.
      _ref.invalidate(providerRatingsProvider);
    } catch (_) {
      // Providers may not be mounted yet (tests, fresh-launch); harmless
      // if they aren't, we just lose the eager refetch.
    }
  }

  /// Refetch GET /users/me so `currentUser.artisanProfile.completedJobsCount`
  /// reflects the just-completed job. Without this the home-screen "Jobs
  /// Done" tile and the profile/earnings stat stay frozen at whatever value
  /// was returned at sign-in. Fire-and-forget — `refreshProfile()` updates
  /// auth state on success and the home screen rebuilds reactively.
  void _refreshUserProfile() {
    try {
      if (!_ref.exists(authControllerProvider)) return;
      unawaited(_ref.read(authControllerProvider.notifier).refreshProfile());
    } catch (_) {
      // Auth controller may not be mounted (tests); harmless.
    }
  }

  String _friendlyCashError(ApiException e) {
    switch (e.errorCode) {
      case 'ARTISAN_PROFILE_REQUIRED':
        return 'Your artisan profile is incomplete. Finish onboarding to '
            'confirm cash payments.';
      case 'NOT_ASSIGNED_ARTISAN':
        return "Only this job's assigned artisan can confirm receipt.";
      case 'PAYSTACK_CHARGE_IN_FLIGHT':
        return "The client started an in-app payment — wait a moment for "
            'it to settle. The job will complete automatically.';
      case 'PAYMENT_RECORD_EXISTS':
        return 'A payment is already on file for this job. Pull down to '
            'refresh and check the status.';
      case 'JOB_NOT_AWAITING_RECEIPT':
        return "This job isn't ready for cash confirmation yet.";
      case 'CLIENT_PAYMENT_NOT_ACKNOWLEDGED':
        return "The client hasn't confirmed they're paying with cash yet. "
            "Ask them to tap 'Proceed to Payment' and pick Cash.";
      case 'AGREED_PRICE_MISSING':
        return "We can't find the agreed price for this job. Contact "
            'support so it can be reconciled manually.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: "Couldn't confirm the payment. Please try again.",
          conflictMessage:
              'The payment state changed. Refresh the job before trying again.',
        );
    }
  }

  Job? _safeParseJob(Map<String, dynamic> json) {
    if ((json['jobId'] is! String && json['id'] is! String) ||
        json['status'] is! String) {
      return null;
    }
    try {
      return Job.fromJson(json);
    } catch (_) {
      return null;
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
      final needsLifecycleFix = next == JobStatus.arrived ||
          next == JobStatus.inProgress ||
          next == JobStatus.artisanMarkedComplete;
      final position = needsLifecycleFix
          ? await _ref
              .read(lifecycleLocationServiceProvider)
              .obtain(_ref.read(lastKnownPositionProvider))
          : null;
      if (position != null) {
        _ref.read(lastKnownPositionProvider.notifier).state = position;
      }
      final acknowledgement =
          await _ref.read(jobServiceProvider).updateJobStatus(
                job.id,
                status: next.toJson(),
                currentLat: position?.latitude,
                currentLng: position?.longitude,
                accuracyMeters: position?.accuracy,
                capturedAt: position?.timestamp,
              );
      if (acknowledgement['status']?.toString() != next.toJson()) {
        developer.debugLog(
          () => 'Job transition response was not authoritative for ${job.id}; '
              'reading the job back before changing local status',
          name: 'ActiveJob',
          level: 900,
        );
        final fresh = await refreshFromServer();
        if (fresh == null || !_hasReachedJobStatus(fresh.status, next)) {
          state = state.copyWith(
            isUpdating: false,
            errorMessage: fresh?.status == JobStatus.cancelled
                ? 'This job was cancelled before the update could finish.'
                : "We couldn't confirm the job update. Keep this job open while we check again.",
          );
          return false;
        }
        state = state.copyWith(isUpdating: false);
        return true;
      }
      // Local fallback for the on-the-job duration ticker. Backend is the
      // source of truth (`started_at` / `completed_at` come back on the
      // next GET /jobs/:id and are merged in via [refreshFromServer]),
      // but until that endpoint ships the new fields the active-job UI
      // would have nothing to show. Stamping locally here means the
      // artisan sees the timer the moment they tap "Start job", and the
      // client sees the same once the backend echoes the timestamps.
      final nowIso = DateTime.now().toUtc().toIso8601String();
      String? startedAt = job.startedAt;
      String? completedAt = job.completedAt;
      if (next == JobStatus.inProgress && startedAt == null) {
        startedAt = nowIso;
      }
      if (next == JobStatus.artisanMarkedComplete && completedAt == null) {
        completedAt = nowIso;
      }
      // Optimistically reflect the new status in-memory so the timeline
      // moves immediately; the backend `job:status` socket event will
      // arrive shortly after and reconcile any drift via a jobs refresh.
      state = state.copyWith(
        job: job.copyWith(
          status: next,
          startedAt: startedAt,
          completedAt: completedAt,
        ),
        isUpdating: false,
      );
      try {
        if (_ref.exists(artisanJobsProvider)) {
          _ref.read(artisanJobsProvider.notifier).silentReload();
        }
      } catch (_) {}
      return true;
    } on LifecycleLocationException catch (e) {
      state = state.copyWith(
        isUpdating: false,
        errorMessage: e.message,
      );
      return false;
    } on ApiException catch (e) {
      developer.debugLog(
        () => 'updateJobStatus failed: ${e.message}',
        name: 'ActiveJob',
        level: 900,
      );
      state = state.copyWith(
        isUpdating: false,
        errorMessage: _friendlyError(e),
      );
      return false;
    } catch (e) {
      developer.debugLog(
        () => 'updateJobStatus crashed: $e',
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
      case 'LIFECYCLE_LOCATION_REQUIRED':
        return 'Get your current GPS location before updating this job.';
      case 'GPS_FIX_STALE':
        return 'MyShop needs a GPS fix from the last 15 seconds. Try again.';
      case 'GPS_ACCURACY_REQUIRED':
        return 'GPS accuracy is too low. Move to an open area and try again.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: 'Could not update the job. Please try again.',
          conflictMessage:
              'The job changed before the update completed. Refresh and try again.',
        );
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

bool _hasReachedJobStatus(JobStatus current, JobStatus target) {
  if (current == JobStatus.cancelled) return false;
  const rank = <JobStatus, int>{
    JobStatus.confirmed: 0,
    JobStatus.artisanEnRoute: 1,
    JobStatus.arrived: 2,
    JobStatus.inProgress: 3,
    JobStatus.artisanMarkedComplete: 4,
    JobStatus.pendingPayment: 5,
    JobStatus.completed: 6,
  };
  return (rank[current] ?? -1) >= (rank[target] ?? 999);
}

final activeJobProvider =
    StateNotifierProvider<ActiveJobNotifier, ActiveJobState>(
  (ref) => ActiveJobNotifier(ref),
);
