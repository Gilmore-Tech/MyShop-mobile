import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import 'submitted_bids_provider.dart';

/// Optional date-range filter applied on top of the tab filter. Null = no
/// date filter (every entry passes through). The range is inclusive on
/// both ends; the filter compares against `job.createdAt`.
final artisanJobsDateFilterProvider =
    StateProvider<DateTimeRange?>((_) => null);

/// Hard cap on the jobs fetch — without this, a stalled backend leaves the
/// spinner up indefinitely because `listJobs` has no built-in deadline.
const _kFetchTimeout = Duration(seconds: 15);

/// Background refresh cadence. Safety net for missed socket events —
/// keeps the bid banner, status pill, and list in sync even when
/// `job:status` / `bid:accepted` never lands.
///
/// Bumped 8 s → 20 s on 14 May. The 8 s cadence + the active-job
/// individual fetch (5 s) + location updates (every 5 s) + chat
/// heartbeat were pushing the per-minute request count past the 100/min
/// throttle ceiling, blocking legitimate users with 429s mid-test.
/// Socket events still drive instant state changes; this just catches
/// the cold-reconnect window.
const _kPollInterval = Duration(seconds: 20);

/// Minimum gap between *silent* reloads. Coalesces bursts where the
/// 8s poll, a `status:changed` socket event, and an active-job state
/// transition all want to refresh the list in the same ~100ms window.
/// User-initiated [ArtisanJobsNotifier.load] is non-silent and exempt
/// — pull-to-refresh + retry buttons always fire.
const _kSilentReloadMinGap = Duration(seconds: 2);

/// A condensed job view for the artisan's "My Jobs" list.
///
/// Wraps the raw [Job] with artisan-specific display data — the amount they
/// bid, when they bid, and whether it was accepted. These fields are read
/// from the backend's enriched `/jobs` response; when absent we fall back
/// to job-level info.
class ArtisanJobEntry {
  const ArtisanJobEntry({
    required this.job,
    this.bidId,
    this.bidAmountPesewas,
    this.bidEtaMinutes,
    this.bidDurationMinutes,
    this.bidMessage,
    this.bidStatus,
    this.bidSubmittedAt,
    this.bidExpiresAt,
  });

  final Job job;

  /// The artisan's bid record id — required to address PATCH/DELETE
  /// `/jobs/:jobId/bids/:bidId` for edit and withdraw flows. Null when
  /// the entry came back from a path that doesn't carry `myBid` (e.g.
  /// a locally-tracked draft that hasn't yet been ACKed by the backend).
  final String? bidId;

  /// The artisan's own bid amount on this job, if they bid.
  final int? bidAmountPesewas;
  final int? bidEtaMinutes;
  final int? bidDurationMinutes;
  final String? bidMessage;

  /// One of: `submitted`, `accepted`, `rejected`, `expired`, `withdrawn`.
  final String? bidStatus;
  final String? bidSubmittedAt;

  /// Backend-authoritative bid window close time. The provider screen
  /// uses this to anchor the pending-bid countdown so a screen open
  /// doesn't reset the clock.
  final String? bidExpiresAt;

  bool get hasBid => bidAmountPesewas != null || bidStatus != null;
  bool get bidAccepted => bidStatus == 'accepted';
  bool get bidRejected =>
      bidStatus == 'rejected' ||
      bidStatus == 'expired' ||
      bidStatus == 'withdrawn' ||
      bidStatus == 'not_selected';
  // Backend may return `submitted`, `pending`, `pending_review`, or leave the
  // status null when only the amount is attached — treat any in-flight bid
  // as submitted so it shows in the "Bids" tab.
  bool get bidSubmitted =>
      bidStatus == 'submitted' ||
      bidStatus == 'pending' ||
      bidStatus == 'pending_review' ||
      (bidStatus == null && bidAmountPesewas != null);

  String get bidAmountDisplay {
    if (bidAmountPesewas == null) return '';
    return 'GHS ${(bidAmountPesewas! / 100).toStringAsFixed(2)}';
  }

  ArtisanJobEntry copyWith({
    Job? job,
    String? bidId,
    int? bidAmountPesewas,
    int? bidEtaMinutes,
    int? bidDurationMinutes,
    String? bidMessage,
    String? bidStatus,
    String? bidSubmittedAt,
    String? bidExpiresAt,
  }) {
    return ArtisanJobEntry(
      job: job ?? this.job,
      bidId: bidId ?? this.bidId,
      bidAmountPesewas: bidAmountPesewas ?? this.bidAmountPesewas,
      bidEtaMinutes: bidEtaMinutes ?? this.bidEtaMinutes,
      bidDurationMinutes: bidDurationMinutes ?? this.bidDurationMinutes,
      bidMessage: bidMessage ?? this.bidMessage,
      bidStatus: bidStatus ?? this.bidStatus,
      bidSubmittedAt: bidSubmittedAt ?? this.bidSubmittedAt,
      bidExpiresAt: bidExpiresAt ?? this.bidExpiresAt,
    );
  }
}

/// Filter buckets for the artisan jobs tab bar.
enum ArtisanJobFilter { newRequests, active, submitted, completed }

extension ArtisanJobFilterX on ArtisanJobFilter {
  String get label => switch (this) {
        ArtisanJobFilter.newRequests => 'New',
        ArtisanJobFilter.active => 'Active',
        ArtisanJobFilter.submitted => 'Bids',
        ArtisanJobFilter.completed => 'Completed',
      };
}

/// Immutable state snapshot for the artisan jobs screen.
class ArtisanJobsState {
  const ArtisanJobsState({
    this.isLoading = true,
    this.errorMessage,
    this.entries = const [],
  });

  final bool isLoading;
  final String? errorMessage;
  final List<ArtisanJobEntry> entries;

  ArtisanJobsState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    List<ArtisanJobEntry>? entries,
  }) =>
      ArtisanJobsState(
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        entries: entries ?? this.entries,
      );
}

/// Fetches the artisan's jobs + bids from the backend.
///
/// Uses `GET /jobs` which (when called by an artisan token) returns jobs
/// the artisan has bid on, been matched to, or been assigned. The backend
/// attaches a `myBid` object to each record with `{ amountPesewas, status,
/// createdAt }` when the artisan has bid.
class ArtisanJobsNotifier extends StateNotifier<ArtisanJobsState> {
  ArtisanJobsNotifier(this._ref) : super(const ArtisanJobsState()) {
    load();
    _startPollTimer();
  }

  final Ref _ref;
  Timer? _pollTimer;
  bool _inFlight = false;
  DateTime? _lastFetchEndAt;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      _kPollInterval,
      (_) => silentReload(),
    );
  }

  /// Stop the background poll. Call when the app is backgrounded so a
  /// suspended-then-resumed iOS process doesn't queue 8s ticks while idle.
  /// FCM is the real wakeup channel for new jobs while the app isn't
  /// foreground; the poll is only a foreground safety net.
  void pausePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Restart the poll and fire one immediate silent reload so the list
  /// reconciles any state we missed while paused.
  void resumePolling() {
    if (_pollTimer != null) return;
    _startPollTimer();
    silentReload();
  }

  Future<void> load() => _fetch(silent: false);

  /// Refresh in the background without flipping [isLoading]. Used by the
  /// poll timer and socket handlers so the list stays live without the UI
  /// ever flashing the spinner.
  Future<void> silentReload() => _fetch(silent: true);

  Future<void> _fetch({required bool silent}) async {
    // Coalesce: socket events + poll timer can overlap during an in-flight
    // fetch — drop duplicates instead of queuing redundant requests.
    if (_inFlight) return;

    // Leading-edge gap for silent reloads: when 429s fail fast, the
    // in-flight flag clears in <100ms and several event-driven reloads
    // (socket status:changed, active-job state transition, etc.) can
    // sequence into a burst that re-trips the global IP throttle. The
    // 8s poll timer keeps data fresh, so dropping bursty silent reloads
    // is safe. User-initiated `load()` is non-silent and never gated.
    if (silent && _lastFetchEndAt != null) {
      final gap = DateTime.now().difference(_lastFetchEndAt!);
      if (gap < _kSilentReloadMinGap) return;
    }

    _inFlight = true;

    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final raw = await _ref
          .read(jobServiceProvider)
          .listJobs(page: 1, limit: 100)
          .timeout(_kFetchTimeout);
      developer.log(
        'Fetched ${raw.length} jobs for artisan${silent ? ' (silent)' : ''}',
        name: 'ArtisanJobs',
      );
      final entries = <ArtisanJobEntry>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        try {
          entries.add(_parse(item));
        } catch (e) {
          developer.log('Skipping unparseable job entry: $e',
              name: 'ArtisanJobs', level: 800);
        }
      }
      final withBid = entries.where((e) => e.hasBid).length;
      developer.log(
        'Parsed ${entries.length} entries ($withBid with a bid attached)',
        name: 'ArtisanJobs',
      );
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        entries: entries,
        clearError: true,
      );
    } on TimeoutException {
      developer.log('Artisan jobs fetch timed out',
          name: 'ArtisanJobs', level: 900);
      if (silent || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage:
            'Taking too long to load. Check your connection and retry.',
      );
    } catch (e, st) {
      // The auth interceptor rejects authed requests with this error
      // string the moment the access token is cleared (logout). The
      // notifier outlives the auth state by a frame or two and the
      // poll timer keeps firing — kill the timer here so the loop
      // self-extinguishes instead of spamming the log.
      final msg = e.toString();
      if (msg.contains('NOT_AUTHENTICATED') ||
          msg.contains('session is over')) {
        developer.log(
            '[ArtisanJobs] session ended — stopping poll timer',
            name: 'ArtisanJobs');
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      developer.log('Failed to load artisan jobs: $e\n$st',
          name: 'ArtisanJobs', level: 900);
      // Silent refreshes must never clobber the last-good list with an
      // error — the user just sees the data they already had.
      if (silent || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load jobs. Pull to retry.',
      );
    } finally {
      _inFlight = false;
      _lastFetchEndAt = DateTime.now();
    }
  }

  ArtisanJobEntry _parse(Map<String, dynamic> json) {
    final job = Job.fromJson(json);
    // Backend may attach the artisan's bid under `myBid` or `bid`. The
    // bid id is sometimes serialised as `bidId` (the public marketplace
    // shape) and sometimes as `id` (raw bid record).
    final myBid = json['myBid'] ?? json['bid'];
    if (myBid is Map<String, dynamic>) {
      return ArtisanJobEntry(
        job: job,
        bidId: (myBid['bidId'] ?? myBid['id']) as String?,
        bidAmountPesewas: (myBid['amountPesewas'] as num?)?.toInt(),
        bidEtaMinutes: (myBid['etaMinutes'] as num?)?.toInt(),
        bidDurationMinutes: (myBid['durationMinutes'] as num?)?.toInt(),
        bidMessage: myBid['message'] as String?,
        bidStatus: myBid['status'] as String?,
        bidSubmittedAt: myBid['createdAt'] as String?,
        bidExpiresAt: myBid['expiresAt'] as String?,
      );
    }
    return ArtisanJobEntry(job: job);
  }
}

final artisanJobsProvider =
    StateNotifierProvider.autoDispose<ArtisanJobsNotifier, ArtisanJobsState>(
  (ref) => ArtisanJobsNotifier(ref),
);

/// Entries filtered for the given tab.
///   - **active**    → jobs the artisan is working on (confirmed through
///                     in_progress / artisan_marked_complete)
///   - **submitted** → every bid the artisan has placed, regardless of the
///                     current job status (pending, accepted, rejected,
///                     expired, or the job moved on without them). Merges
///                     local tracker entries so bids never disappear.
///   - **completed** → finished or cancelled jobs they were assigned to
///
/// Entries in the `submitted` filter are enriched with local bid data
/// (amount, ETA, duration, submittedAt, expiresAt) so the cards render
/// accurate values even when the backend omits `myBid`.
final artisanJobsFilteredProvider = Provider.autoDispose
    .family<List<ArtisanJobEntry>, ArtisanJobFilter>((ref, filter) {
  final state = ref.watch(artisanJobsProvider);
  final localBids = ref.watch(submittedBidsProvider);
  final dateFilter = ref.watch(artisanJobsDateFilterProvider);

  // 1. Enrich every backend entry with local bid data when present.
  //    Also merge client identity (name/phone/photo) and cosmetic fields
  //    (categoryName, addressText) from the saved bid's Job snapshot —
  //    the backend `GET /jobs` feed drops these, so without this the
  //    Bids tab card and any subsequent screens fall back to "Client" +
  //    a generic avatar even though we captured the rich data at bid
  //    submission time.
  final results = <ArtisanJobEntry>[];
  final seenJobIds = <String>{};
  for (final entry in state.entries) {
    final local = localBids[entry.job.id];
    final ArtisanJobEntry enriched;
    if (local != null) {
      final mergedJob = entry.job.copyWith(
        clientName: entry.job.clientName ?? local.job.clientName,
        clientPhone: entry.job.clientPhone ?? local.job.clientPhone,
        clientPhotoUrl: entry.job.clientPhotoUrl ?? local.job.clientPhotoUrl,
        categoryName: entry.job.categoryName ?? local.job.categoryName,
        addressText: entry.job.addressText ?? local.job.addressText,
      );
      enriched = entry.copyWith(
        job: mergedJob,
        bidAmountPesewas: entry.bidAmountPesewas ?? local.amountPesewas,
        bidStatus: entry.bidStatus ?? 'submitted',
        bidSubmittedAt:
            entry.bidSubmittedAt ?? local.submittedAt.toIso8601String(),
      );
    } else {
      enriched = entry;
    }
    if (_matches(enriched, filter)) results.add(enriched);
    seenJobIds.add(entry.job.id);
  }

  // 2. For the "submitted" tab, add locally-tracked bids the backend didn't
  //    return at all. Uses the Job snapshot we captured at submit time.
  if (filter == ArtisanJobFilter.submitted) {
    final onlyLocal = localBids.values
        .where((bid) => !seenJobIds.contains(bid.jobId))
        .toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    for (final bid in onlyLocal) {
      results.add(
        ArtisanJobEntry(
          job: bid.job,
          bidAmountPesewas: bid.amountPesewas,
          bidStatus: 'submitted',
          bidSubmittedAt: bid.submittedAt.toIso8601String(),
        ),
      );
    }
  }

  // 3. Apply the optional date-range filter against `job.createdAt`.
  //    Entries with an unparseable / missing timestamp drop out — without
  //    a date we can't decide which side of the range they're on.
  if (dateFilter == null) return results;
  return results.where((e) => _inDateRange(e.job.createdAt, dateFilter)).toList();
});

/// True when [iso] falls inside [range] (inclusive on both ends, day-level
/// precision). Returns false for null / unparseable timestamps so they
/// never sneak past a filter the user intentionally set.
bool _inDateRange(String? iso, DateTimeRange range) {
  if (iso == null) return false;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return false;
  final local = dt.toLocal();
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final endExclusive = DateTime(
    range.end.year,
    range.end.month,
    range.end.day,
  ).add(const Duration(days: 1));
  return !local.isBefore(start) && local.isBefore(endExclusive);
}

bool _matches(ArtisanJobEntry entry, ArtisanJobFilter filter) {
  final status = entry.job.status;
  switch (filter) {
    case ArtisanJobFilter.newRequests:
      // Sourced from a separate in-memory provider — never matched here.
      return false;
    case ArtisanJobFilter.active:
      return status == JobStatus.confirmed ||
          status == JobStatus.artisanEnRoute ||
          status == JobStatus.arrived ||
          status == JobStatus.inProgress ||
          status == JobStatus.artisanMarkedComplete;
    case ArtisanJobFilter.submitted:
      // Every bid the artisan has placed stays here — even after the job
      // gets assigned to someone else or is cancelled. The card shows the
      // outcome (pending / accepted / not selected / expired) so the
      // artisan can always track their bidding history.
      //
      // Directed-quote jobs (admin routed this job to the artisan and is
      // waiting for their price) also live here even before a bid exists —
      // otherwise an `admin_assigned` job is neither active nor completed
      // and would only be reachable via the push notification. Surfacing it
      // in Bids lets the artisan find it and quote at their own pace.
      return entry.hasBid || status == JobStatus.adminAssigned;
    case ArtisanJobFilter.completed:
      return status == JobStatus.completed || status == JobStatus.cancelled;
  }
}
