import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../services/providers/job_detail_provider.dart';

// ── Filter Tab ────────────────────────────────────────────────────────────────
// Maps to the tab bar: All | Active | Completed | Cancelled | Suspended
// API query param: GET /v1/jobs?status=<filter>&page=1&limit=20

enum RequestFilter {
  all,
  active,
  completed,
  cancelled,
  suspended,
}

extension RequestFilterX on RequestFilter {
  String get label => switch (this) {
        RequestFilter.all       => 'All',
        RequestFilter.active    => 'Active',
        RequestFilter.completed => 'Completed',
        RequestFilter.cancelled => 'Cancelled',
        RequestFilter.suspended => 'Suspended',
      };

  /// Statuses that belong to each filter tab.
  /// active tab covers every in-progress state from queued → inProgress.
  Set<JobStatus>? get statuses => switch (this) {
        RequestFilter.all       => null, // fetch everything
        RequestFilter.active    => {
            JobStatus.queued,
            JobStatus.open,
            JobStatus.confirmed,
            JobStatus.enRoute,
            JobStatus.arrived,
            JobStatus.inProgress,
            JobStatus.artisanMarkedComplete,
          },
        RequestFilter.completed => {JobStatus.completed},
        RequestFilter.cancelled => {JobStatus.cancelled},
        RequestFilter.suspended => {}, // placeholder: no suspended status yet in v1
      };
}

// ── Job List Item ─────────────────────────────────────────────────────────────
// Lightweight model used in the list — full details loaded lazily on tap.
// API: GET /v1/jobs  (EDD § Marketplace Endpoints)

class JobListItem {
  final String id;
  final String title;
  final String categoryName;
  final IconData categoryIcon;
  final String location;

  /// Human-readable relative time string, e.g. "Posted 2 hours ago", "6 days ago".
  final String postedAt;

  final JobStatus status;

  /// Non-null only when job is in an active bid-collecting state.
  final int? activeBidCount;

  /// Client's original budget in pesewas (shown in the bid sheet header card).
  final int budgetPesewas;

  const JobListItem({
    required this.id,
    required this.title,
    required this.categoryName,
    required this.categoryIcon,
    required this.location,
    required this.postedAt,
    required this.status,
    required this.budgetPesewas,
    this.activeBidCount,
  });

  /// True if the "X Bidders active — View Bids" row should be shown.
  bool get showBidRow =>
      activeBidCount != null &&
      activeBidCount! > 0 &&
      status == JobStatus.open;
}

// ── Activity State ────────────────────────────────────────────────────────────

class ActivityState {
  final RequestFilter activeFilter;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;
  final List<JobListItem> jobs;

  const ActivityState({
    this.activeFilter = RequestFilter.all,
    this.searchQuery = '',
    this.isLoading = true,
    this.errorMessage,
    this.jobs = const [],
  });

  ActivityState copyWith({
    RequestFilter? activeFilter,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
    List<JobListItem>? jobs,
    bool clearError = false,
  }) =>
      ActivityState(
        activeFilter: activeFilter ?? this.activeFilter,
        searchQuery: searchQuery ?? this.searchQuery,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        jobs: jobs ?? this.jobs,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ActivityNotifier extends StateNotifier<ActivityState> {
  final Ref _ref;

  ActivityNotifier(this._ref) : super(const ActivityState()) {
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    try {
      final jobService = _ref.read(jobServiceProvider);
      final data = await jobService.listJobs(page: 1, limit: 50);

      final jobs = <JobListItem>[];
      for (final j in data) {
        if (j is! Map<String, dynamic>) continue;
        jobs.add(_parseJobListItem(j));
      }

      state = state.copyWith(
        isLoading: false,
        jobs: jobs,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load jobs. Pull to retry.',
      );
    }
  }

  Future<void> reload() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _loadJobs();
  }

  void setFilter(RequestFilter filter) =>
      state = state.copyWith(activeFilter: filter);

  void setSearch(String query) =>
      state = state.copyWith(searchQuery: query);

  void clearSearch() => state = state.copyWith(searchQuery: '');

  // ── Parsing ──────────────────────────────────────────────────────────────

  static JobListItem _parseJobListItem(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'open';
    final status = _parseJobStatus(statusStr);
    final description = json['description'] as String? ?? '';
    final category = json['category'] as Map<String, dynamic>?;
    final categoryName = category?['name'] as String? ?? 'Service';
    final addressText = json['addressText'] as String? ?? '';
    final bids = json['bids'] as List<dynamic>?;
    final createdAt = json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String)
        : null;

    return JobListItem(
      id: json['id'] as String? ?? '',
      title: description,
      categoryName: categoryName,
      categoryIcon: _categoryIcon(categoryName),
      location: addressText,
      postedAt: createdAt != null ? _relativeTime(createdAt) : '',
      status: status,
      budgetPesewas: (json['budgetPesewas'] as int?) ?? 0,
      activeBidCount:
          status == JobStatus.open ? (bids?.length ?? 0) : null,
    );
  }

  static JobStatus _parseJobStatus(String status) {
    return switch (status) {
      'queued'                  => JobStatus.queued,
      'open'                    => JobStatus.open,
      'confirmed'               => JobStatus.confirmed,
      'en_route'                => JobStatus.enRoute,
      'arrived'                 => JobStatus.arrived,
      'in_progress'             => JobStatus.inProgress,
      'artisan_marked_complete' => JobStatus.artisanMarkedComplete,
      'completed'               => JobStatus.completed,
      'cancelled'               => JobStatus.cancelled,
      _                         => JobStatus.open,
    };
  }

  static IconData _categoryIcon(String categoryName) {
    final lower = categoryName.toLowerCase();
    if (lower.contains('plumb')) return Icons.plumbing;
    if (lower.contains('electr')) return Icons.electrical_services;
    if (lower.contains('carpen') || lower.contains('wood')) return Icons.carpenter;
    if (lower.contains('paint')) return Icons.format_paint;
    if (lower.contains('clean')) return Icons.cleaning_services;
    if (lower.contains('tow') || lower.contains('car')) return Icons.car_repair;
    if (lower.contains('delivery') || lower.contains('package')) return Icons.local_shipping;
    return Icons.work_outline_rounded;
  }

  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Posted just now';
    if (diff.inMinutes < 60) return 'Posted ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Posted ${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Posted yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    return '${(diff.inDays / 30).floor()} months ago';
  }
}

final activityNotifierProvider =
    StateNotifierProvider.autoDispose<ActivityNotifier, ActivityState>(
  (ref) => ActivityNotifier(ref),
);

// ── Job List Provider ─────────────────────────────────────────────────────────
// Derives the visible list from the current filter + search state.

final filteredJobsProvider = Provider.autoDispose<List<JobListItem>>((ref) {
  final state = ref.watch(activityNotifierProvider);
  final filter = state.activeFilter;
  final query  = state.searchQuery.trim().toLowerCase();

  var jobs = List<JobListItem>.from(state.jobs);

  // Apply status filter
  final allowedStatuses = filter.statuses;
  if (allowedStatuses != null) {
    jobs = jobs
        .where((j) => allowedStatuses.contains(j.status))
        .toList();
  }

  // Apply search filter
  if (query.isNotEmpty) {
    jobs = jobs
        .where((j) =>
            j.title.toLowerCase().contains(query) ||
            j.categoryName.toLowerCase().contains(query) ||
            j.location.toLowerCase().contains(query))
        .toList();
  }

  return jobs;
});

// ── Active job count for the bottom nav badge ──────────────────────────────────

final activeJobCountProvider = Provider.autoDispose<int>((ref) {
  final state = ref.watch(activityNotifierProvider);
  return state.jobs
      .where((j) =>
          RequestFilter.active.statuses?.contains(j.status) ?? false)
      .length;
});
