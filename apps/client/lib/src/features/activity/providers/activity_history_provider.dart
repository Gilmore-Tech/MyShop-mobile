import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Activity Filter ───────────────────────────────────────────────────────────

enum ActivityFilter { all, rides, jobs }

extension ActivityFilterX on ActivityFilter {
  String get label => switch (this) {
        ActivityFilter.all   => 'All',
        ActivityFilter.rides => 'Rides',
        ActivityFilter.jobs  => 'Jobs',
      };

  IconData get icon => switch (this) {
        ActivityFilter.all   => Icons.filter_list_rounded,
        ActivityFilter.rides => Icons.directions_car_outlined,
        ActivityFilter.jobs  => Icons.work_outline_rounded,
      };
}

// ── Transaction Type & Status ─────────────────────────────────────────────────

enum TransactionType { ride, job }

enum TransactionStatus { completed, cancelled, inProgress, pending }

extension TransactionStatusX on TransactionStatus {
  String get label => switch (this) {
        TransactionStatus.completed  => 'Completed',
        TransactionStatus.cancelled  => 'Cancelled',
        TransactionStatus.inProgress => 'In Progress',
        TransactionStatus.pending    => 'Pending',
      };

  Color get badgeBg => switch (this) {
        TransactionStatus.completed  => const Color(0xFFE8F8EF),
        TransactionStatus.cancelled  => const Color(0xFFFDE8E8),
        TransactionStatus.inProgress => const Color(0xFFFEF3E8),
        TransactionStatus.pending    => const Color(0xFFE8F0FD),
      };

  Color get badgeFg => switch (this) {
        TransactionStatus.completed  => const Color(0xFF27AE60),
        TransactionStatus.cancelled  => const Color(0xFFEB5757),
        TransactionStatus.inProgress => const Color(0xFFF2994A),
        TransactionStatus.pending    => const Color(0xFF2F80ED),
      };

  IconData get badgeIcon => switch (this) {
        TransactionStatus.completed  => Icons.check_circle_outline_rounded,
        TransactionStatus.cancelled  => Icons.cancel_outlined,
        TransactionStatus.inProgress => Icons.timelapse_rounded,
        TransactionStatus.pending    => Icons.schedule_rounded,
      };
}

// ── Transaction Item ──────────────────────────────────────────────────────────
// Unified lightweight model for both rides and artisan jobs.
// Rides API:  GET /v1/rides  (page, limit, status filter)
// Jobs  API:  GET /v1/jobs   (page, limit, status filter)

class TransactionItem {
  final String            id;
  final TransactionType   type;
  final String            title;

  /// For rides: "Pickup → Dropoff". For jobs: single location string.
  final String            locationLabel;

  /// Display timestamp, e.g. "08:45 AM" (today) or "Oct 23, 10:00 AM" (past).
  final String            timeLabel;

  final TransactionStatus status;

  const TransactionItem({
    required this.id,
    required this.type,
    required this.title,
    required this.locationLabel,
    required this.timeLabel,
    required this.status,
  });

  IconData get typeIcon => switch (type) {
        TransactionType.ride => Icons.directions_car_outlined,
        TransactionType.job  => Icons.work_outline_rounded,
      };
}

// ── Date Group ────────────────────────────────────────────────────────────────

class TransactionGroup {
  final String              label; // "TODAY", "YESTERDAY", "LAST WEEK"
  final List<TransactionItem> items;
  const TransactionGroup({required this.label, required this.items});
}

// ── Monthly Summary ───────────────────────────────────────────────────────────

class ActivitySummary {
  final int    monthlySpendPesewas; // displayed as GH¢ X,XXX.XX
  final int    tripCount;
  final String monthLabel;          // "October"

  const ActivitySummary({
    required this.monthlySpendPesewas,
    required this.tripCount,
    required this.monthLabel,
  });

  /// "GH¢ 1,240.50"
  String get formattedSpend {
    final ghs = monthlySpendPesewas / 100.0;
    final intPart = ghs.floor();
    final decPart = ((ghs - intPart) * 100).round();
    final formatted = intPart.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
    return 'GH¢ $formatted.${decPart.toString().padLeft(2, '0')}';
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class ActivityHistoryState {
  final ActivityFilter           filter;
  final String                   searchQuery;
  final bool                     isLoading;
  final ActivitySummary?         summary;
  final List<TransactionGroup>   groups;
  final String?                  errorMessage;

  const ActivityHistoryState({
    this.filter      = ActivityFilter.all,
    this.searchQuery = '',
    this.isLoading   = true,
    this.summary,
    this.groups      = const [],
    this.errorMessage,
  });

  ActivityHistoryState copyWith({
    ActivityFilter?          filter,
    String?                  searchQuery,
    bool?                    isLoading,
    ActivitySummary?         summary,
    List<TransactionGroup>?  groups,
    String?                  errorMessage,
    bool                     clearError = false,
  }) =>
      ActivityHistoryState(
        filter:       filter       ?? this.filter,
        searchQuery:  searchQuery  ?? this.searchQuery,
        isLoading:    isLoading    ?? this.isLoading,
        summary:      summary      ?? this.summary,
        groups:       groups       ?? this.groups,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ActivityHistoryNotifier
    extends StateNotifier<ActivityHistoryState> {
  ActivityHistoryNotifier() : super(const ActivityHistoryState()) {
    _load();
  }

  Future<void> _load() async {
    // TODO: GET /v1/rides?page=1&limit=50  +  GET /v1/jobs?page=1&limit=50
    //       Merge by createdAt descending, group by date bucket.
    await Future.delayed(const Duration(milliseconds: 350));
    state = state.copyWith(
      isLoading: false,
      summary: const ActivitySummary(
        monthlySpendPesewas: 124050,  // GH¢ 1,240.50
        tripCount:           24,
        monthLabel:          'October',
      ),
      groups: _mockGroups,
    );
  }

  Future<void> reload() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _load();
  }

  void setFilter(ActivityFilter f) =>
      state = state.copyWith(filter: f, clearError: true);

  void setSearch(String q) =>
      state = state.copyWith(searchQuery: q, clearError: true);

  void clearSearch() => state = state.copyWith(searchQuery: '');
}

final activityHistoryProvider = StateNotifierProvider.autoDispose<
    ActivityHistoryNotifier, ActivityHistoryState>(
  (_) => ActivityHistoryNotifier(),
);

// ── Derived: filtered groups ──────────────────────────────────────────────────

final filteredActivityGroupsProvider =
    Provider.autoDispose<List<TransactionGroup>>((ref) {
  final state = ref.watch(activityHistoryProvider);
  final filter = state.filter;
  final query  = state.searchQuery.trim().toLowerCase();

  List<TransactionItem> filterItems(List<TransactionItem> items) {
    var result = items;
    if (filter != ActivityFilter.all) {
      final wantType = filter == ActivityFilter.rides
          ? TransactionType.ride
          : TransactionType.job;
      result = result.where((i) => i.type == wantType).toList();
    }
    if (query.isNotEmpty) {
      result = result
          .where((i) =>
              i.title.toLowerCase().contains(query) ||
              i.locationLabel.toLowerCase().contains(query) ||
              i.id.toLowerCase().contains(query))
          .toList();
    }
    return result;
  }

  return state.groups
      .map((g) => TransactionGroup(
            label: g.label,
            items: filterItems(g.items),
          ))
      .where((g) => g.items.isNotEmpty)
      .toList();
});

// ── Mock data ─────────────────────────────────────────────────────────────────

const _mockGroups = <TransactionGroup>[
  TransactionGroup(
    label: 'TODAY',
    items: [
      TransactionItem(
        id:            'RIDE-2041',
        type:          TransactionType.ride,
        title:         'Work Shuttle (Corporate)',
        locationLabel: 'Airport Residential Area → Ridge',
        timeLabel:     '08:45 AM',
        status:        TransactionStatus.completed,
      ),
    ],
  ),
  TransactionGroup(
    label: 'YESTERDAY',
    items: [
      TransactionItem(
        id:            'JOB-1092',
        type:          TransactionType.job,
        title:         'Office Cleaning Service',
        locationLabel: 'Labone Heights Estate',
        timeLabel:     'Oct 23, 10:00 AM',
        status:        TransactionStatus.completed,
      ),
      TransactionItem(
        id:            'RIDE-2040',
        type:          TransactionType.ride,
        title:         'Late Night Ride',
        locationLabel: 'Bloombar → East Legon',
        timeLabel:     'Oct 23, 11:45 PM',
        status:        TransactionStatus.cancelled,
      ),
    ],
  ),
  TransactionGroup(
    label: 'LAST WEEK',
    items: [
      TransactionItem(
        id:            'RIDE-2039',
        type:          TransactionType.ride,
        title:         'Intercity Trip',
        locationLabel: 'Accra → Kumasi Central',
        timeLabel:     'Oct 18, 06:15 AM',
        status:        TransactionStatus.completed,
      ),
      TransactionItem(
        id:            'JOB-1088',
        type:          TransactionType.job,
        title:         'Package Delivery',
        locationLabel: 'Tema Port → Spintex Road',
        timeLabel:     'Oct 17, 02:30 PM',
        status:        TransactionStatus.completed,
      ),
    ],
  ),
];
