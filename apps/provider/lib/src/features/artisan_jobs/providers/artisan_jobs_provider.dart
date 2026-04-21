import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import 'submitted_bids_provider.dart';

/// A condensed job view for the artisan's "My Jobs" list.
///
/// Wraps the raw [Job] with artisan-specific display data — the amount they
/// bid, when they bid, and whether it was accepted. These fields are read
/// from the backend's enriched `/jobs` response; when absent we fall back
/// to job-level info.
class ArtisanJobEntry {
  const ArtisanJobEntry({
    required this.job,
    this.bidAmountPesewas,
    this.bidStatus,
    this.bidSubmittedAt,
  });

  final Job job;

  /// The artisan's own bid amount on this job, if they bid.
  final int? bidAmountPesewas;

  /// One of: `submitted`, `accepted`, `rejected`, `expired`, `withdrawn`.
  final String? bidStatus;
  final String? bidSubmittedAt;

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
    int? bidAmountPesewas,
    String? bidStatus,
    String? bidSubmittedAt,
  }) {
    return ArtisanJobEntry(
      job: job ?? this.job,
      bidAmountPesewas: bidAmountPesewas ?? this.bidAmountPesewas,
      bidStatus: bidStatus ?? this.bidStatus,
      bidSubmittedAt: bidSubmittedAt ?? this.bidSubmittedAt,
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
  }

  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final raw =
          await _ref.read(jobServiceProvider).listJobs(page: 1, limit: 100);
      developer.log(
        'Fetched ${raw.length} jobs for artisan',
        name: 'ArtisanJobs',
      );
      final entries = <ArtisanJobEntry>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        entries.add(_parse(item));
      }
      final withBid = entries.where((e) => e.hasBid).length;
      developer.log(
        'Parsed ${entries.length} entries ($withBid with a bid attached)',
        name: 'ArtisanJobs',
      );
      state = state.copyWith(isLoading: false, entries: entries);
    } catch (e) {
      developer.log('Failed to load artisan jobs: $e',
          name: 'ArtisanJobs', level: 900);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load jobs. Pull to retry.',
      );
    }
  }

  ArtisanJobEntry _parse(Map<String, dynamic> json) {
    final job = Job.fromJson(json);
    // Backend may attach the artisan's bid under `myBid` or `bid`.
    final myBid = json['myBid'] ?? json['bid'];
    if (myBid is Map<String, dynamic>) {
      return ArtisanJobEntry(
        job: job,
        bidAmountPesewas: (myBid['amountPesewas'] as num?)?.toInt(),
        bidStatus: myBid['status'] as String?,
        bidSubmittedAt: myBid['createdAt'] as String?,
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

  // 1. Enrich every backend entry with local bid data when present.
  final results = <ArtisanJobEntry>[];
  final seenJobIds = <String>{};
  for (final entry in state.entries) {
    final local = localBids[entry.job.id];
    final enriched = local != null
        ? entry.copyWith(
            bidAmountPesewas:
                entry.bidAmountPesewas ?? local.amountPesewas,
            bidStatus: entry.bidStatus ?? 'submitted',
            bidSubmittedAt:
                entry.bidSubmittedAt ?? local.submittedAt.toIso8601String(),
          )
        : entry;
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
  return results;
});

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
      return entry.hasBid;
    case ArtisanJobFilter.completed:
      return status == JobStatus.completed || status == JobStatus.cancelled;
  }
}
