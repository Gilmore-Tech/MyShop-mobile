import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            JobStatus.pending,
            JobStatus.bidsReceived,
            JobStatus.selectingArtisan,
            JobStatus.confirmed,
            JobStatus.enRoute,
            JobStatus.arrived,
            JobStatus.inProgress,
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
      (status == JobStatus.bidsReceived ||
          status == JobStatus.selectingArtisan);
}

// ── Activity State ────────────────────────────────────────────────────────────

class ActivityState {
  final RequestFilter activeFilter;
  final String searchQuery;

  const ActivityState({
    this.activeFilter = RequestFilter.all,
    this.searchQuery = '',
  });

  ActivityState copyWith({
    RequestFilter? activeFilter,
    String? searchQuery,
  }) =>
      ActivityState(
        activeFilter: activeFilter ?? this.activeFilter,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ActivityNotifier extends StateNotifier<ActivityState> {
  ActivityNotifier() : super(const ActivityState());

  void setFilter(RequestFilter filter) =>
      state = state.copyWith(activeFilter: filter);

  void setSearch(String query) =>
      state = state.copyWith(searchQuery: query);

  void clearSearch() => state = state.copyWith(searchQuery: '');
}

final activityNotifierProvider =
    StateNotifierProvider.autoDispose<ActivityNotifier, ActivityState>(
  (_) => ActivityNotifier(),
);

// ── Mock data ─────────────────────────────────────────────────────────────────

const _mockJobs = [
  JobListItem(
    id: 'JOB-1001',
    title: 'Fix Leaking Kitchen Pipe',
    categoryName: 'Plumber',
    categoryIcon: Icons.plumbing,
    location: 'Kumasi, Adum',
    postedAt: 'Posted 2 hours ago',
    status: JobStatus.selectingArtisan,
    budgetPesewas: 25000, // GHS 250
    activeBidCount: 5,
  ),
  JobListItem(
    id: 'JOB-1002',
    title: 'Install Ceiling Fan',
    categoryName: 'Electrician',
    categoryIcon: Icons.electrical_services,
    location: 'Accra, Osu',
    postedAt: '6 days ago',
    status: JobStatus.completed,
    budgetPesewas: 18000, // GHS 180
  ),
  JobListItem(
    id: 'JOB-1003',
    title: 'Emergency Roadside Assistance',
    categoryName: 'Towing Car',
    categoryIcon: Icons.car_repair,
    location: 'Takoradi, Market Circle',
    postedAt: '30 days ago',
    status: JobStatus.completed,
    budgetPesewas: 35000, // GHS 350
  ),
  JobListItem(
    id: 'JOB-1004',
    title: 'Custom Wooden Wardrobe',
    categoryName: 'Carpenter',
    categoryIcon: Icons.carpenter,
    location: 'Takoradi, Market Circle',
    postedAt: '30 days ago',
    status: JobStatus.cancelled,
    budgetPesewas: 80000, // GHS 800
  ),
  JobListItem(
    id: 'JOB-1005',
    title: 'Paint Master Bedroom',
    categoryName: 'Painter',
    categoryIcon: Icons.format_paint,
    location: 'Kumasi, Bantama',
    postedAt: '45 days ago',
    status: JobStatus.completed,
    budgetPesewas: 22000, // GHS 220
  ),
];

// ── Job List Provider ─────────────────────────────────────────────────────────
// Derives the visible list from the current filter + search state.
// TODO: replace with real GET /v1/jobs?status=<filter>&q=<search> via API client

final filteredJobsProvider = Provider.autoDispose<List<JobListItem>>((ref) {
  final state = ref.watch(activityNotifierProvider);
  final filter = state.activeFilter;
  final query  = state.searchQuery.trim().toLowerCase();

  var jobs = List<JobListItem>.from(_mockJobs);

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

final activeJobCountProvider = Provider<int>((ref) {
  return _mockJobs
      .where((j) =>
          RequestFilter.active.statuses?.contains(j.status) ?? false)
      .length;
});
