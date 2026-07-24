import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/app_lifecycle_provider.dart';

/// Background poll cadence. Acts as a safety net for missed socket events —
/// when the socket is healthy this fetches the same data and the UI no-ops.
const _kActivityPollInterval = Duration(seconds: 15);

// ── Activity Filter ───────────────────────────────────────────────────────────

enum ActivityFilter { all, rides, jobs }

extension ActivityFilterX on ActivityFilter {
  String get label => switch (this) {
        ActivityFilter.all => 'All',
        ActivityFilter.rides => 'Rides',
        ActivityFilter.jobs => 'Jobs',
      };

  IconData get icon => switch (this) {
        ActivityFilter.all => Icons.filter_list_rounded,
        ActivityFilter.rides => Icons.directions_car_outlined,
        ActivityFilter.jobs => Icons.work_outline_rounded,
      };
}

// ── Transaction Type & Status ─────────────────────────────────────────────────

enum TransactionType { ride, job }

enum TransactionStatus { completed, cancelled, inProgress, pending }

extension TransactionStatusX on TransactionStatus {
  String get label => switch (this) {
        TransactionStatus.completed => 'Completed',
        TransactionStatus.cancelled => 'Cancelled',
        TransactionStatus.inProgress => 'In Progress',
        TransactionStatus.pending => 'Pending',
      };

  Color get badgeBg => switch (this) {
        TransactionStatus.completed => MyShopColors.successLight,
        TransactionStatus.cancelled => MyShopColors.errorLight,
        TransactionStatus.inProgress => MyShopColors.warningLight,
        TransactionStatus.pending => MyShopColors.infoLight,
      };

  Color get badgeFg => switch (this) {
        TransactionStatus.completed => MyShopColors.success,
        TransactionStatus.cancelled => MyShopColors.error,
        TransactionStatus.inProgress => MyShopColors.warning,
        TransactionStatus.pending => MyShopColors.info,
      };

  IconData get badgeIcon => switch (this) {
        TransactionStatus.completed => Icons.check_circle_outline_rounded,
        TransactionStatus.cancelled => Icons.cancel_outlined,
        TransactionStatus.inProgress => Icons.timelapse_rounded,
        TransactionStatus.pending => Icons.schedule_rounded,
      };
}

// ── Transaction Item ──────────────────────────────────────────────────────────
// Unified lightweight model for both rides and artisan jobs.

class TransactionItem {
  final String id;
  final TransactionType type;
  final String title;

  /// For rides: "Pickup → Dropoff". For jobs: single location string.
  final String locationLabel;

  /// Display timestamp, e.g. "08:45 AM" (today) or "Oct 23, 10:00 AM" (past).
  final String timeLabel;

  final TransactionStatus status;

  /// Original creation time — used for sorting and date grouping.
  final DateTime createdAt;

  /// Amount in pesewas — used for monthly spend summary.
  final int amountPesewas;

  const TransactionItem({
    required this.id,
    required this.type,
    required this.title,
    required this.locationLabel,
    required this.timeLabel,
    required this.status,
    required this.createdAt,
    this.amountPesewas = 0,
  });

  IconData get typeIcon => switch (type) {
        TransactionType.ride => Icons.directions_car_outlined,
        TransactionType.job => Icons.work_outline_rounded,
      };
}

// ── Date Group ────────────────────────────────────────────────────────────────

class TransactionGroup {
  final String label; // "TODAY", "YESTERDAY", "LAST WEEK"
  final List<TransactionItem> items;
  const TransactionGroup({required this.label, required this.items});
}

// ── Monthly Summary ───────────────────────────────────────────────────────────

class ActivitySummary {
  final int monthlySpendPesewas; // displayed as GH¢ X,XXX.XX
  final int tripCount;
  final String monthLabel; // "October"

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
  final ActivityFilter filter;
  final String searchQuery;
  final bool isLoading;
  final ActivitySummary? summary;
  final List<TransactionGroup> groups;
  final String? errorMessage;

  const ActivityHistoryState({
    this.filter = ActivityFilter.all,
    this.searchQuery = '',
    this.isLoading = true,
    this.summary,
    this.groups = const [],
    this.errorMessage,
  });

  ActivityHistoryState copyWith({
    ActivityFilter? filter,
    String? searchQuery,
    bool? isLoading,
    ActivitySummary? summary,
    List<TransactionGroup>? groups,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ActivityHistoryState(
        filter: filter ?? this.filter,
        searchQuery: searchQuery ?? this.searchQuery,
        isLoading: isLoading ?? this.isLoading,
        summary: summary ?? this.summary,
        groups: groups ?? this.groups,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ActivityHistoryNotifier extends StateNotifier<ActivityHistoryState> {
  final Ref _ref;
  Timer? _pollTimer;
  bool _inFlight = false;

  ActivityHistoryNotifier(this._ref) : super(const ActivityHistoryState()) {
    _load();
    _pollTimer = Timer.periodic(
      _kActivityPollInterval,
      (_) {
        if (!_ref.read(appForegroundedProvider)) return;
        silentReload();
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    // Coalesce concurrent fetches — socket events and the poll timer can
    // both fire during an in-flight request. Drop duplicates silently.
    if (_inFlight) return;
    _inFlight = true;
    try {
      final rideService = _ref.read(rideServiceProvider);
      final jobService = _ref.read(jobServiceProvider);

      // Fetch rides and jobs in parallel.
      final results = await Future.wait([
        rideService.listRides(page: 1, limit: 50),
        jobService.listJobs(page: 1, limit: 50),
      ]);

      final ridesJson = results[0];
      final jobsJson = results[1];

      // Parse into unified TransactionItems.
      final items = <TransactionItem>[];

      for (final r in ridesJson) {
        if (r is! Map<String, dynamic>) continue;
        try {
          final ride = Ride.fromJson(r);
          items.add(_rideToTransaction(ride));
        } catch (e) {
          debugLog(() =>
              '[Activity] rejected malformed ride entry: ${e.runtimeType}');
        }
      }

      for (final j in jobsJson) {
        if (j is! Map<String, dynamic>) continue;
        try {
          items.add(_jobJsonToTransaction(j));
        } catch (e) {
          debugLog(() =>
              '[Activity] rejected malformed job entry: ${e.runtimeType}');
        }
      }

      // Sort by createdAt descending (newest first).
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Group by date bucket.
      final groups = _groupByDate(items);

      // Build monthly summary from current month's items.
      final now = DateTime.now();
      final monthItems = items.where((i) =>
          i.createdAt.year == now.year && i.createdAt.month == now.month);
      final monthlySpend =
          monthItems.fold<int>(0, (sum, i) => sum + i.amountPesewas);
      final summary = ActivitySummary(
        monthlySpendPesewas: monthlySpend,
        tripCount: monthItems.length,
        monthLabel: DateFormat.MMMM().format(now),
      );

      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        summary: summary,
        groups: groups,
        clearError: true,
      );
    } catch (e) {
      // The auth interceptor rejects authed requests with this error
      // string the moment the token is cleared (logout). The poll timer
      // outlives the auth state by a frame or two — kill it so the loop
      // self-extinguishes instead of pegging the main thread with 401s.
      final msg = e.toString();
      if (msg.contains('NOT_AUTHENTICATED') ||
          msg.contains('session is over')) {
        debugLog(() => '[Activity] session ended — stopping poll timer');
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      // Swallow transient failures on silent refreshes so the UI keeps
      // showing the last known data instead of flipping to an error state.
      if (silent || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load activity. Pull to retry.',
      );
    } finally {
      _inFlight = false;
    }
  }

  Future<void> reload() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _load();
  }

  /// Refresh in the background without toggling [isLoading].
  /// Triggered by socket events and the poll timer so the list stays fresh
  /// without the user seeing a skeleton flash.
  Future<void> silentReload() => _load(silent: true);

  void setFilter(ActivityFilter f) =>
      state = state.copyWith(filter: f, clearError: true);

  void setSearch(String q) =>
      state = state.copyWith(searchQuery: q, clearError: true);

  void clearSearch() => state = state.copyWith(searchQuery: '');

  // ── Helpers ──────────────────────────────────────────────────────────────

  TransactionItem _rideToTransaction(Ride ride) {
    return TransactionItem(
      id: ride.id,
      type: TransactionType.ride,
      title: '${ride.pickupAddress} → ${ride.dropoffAddress}',
      locationLabel: '${ride.pickupAddress} → ${ride.dropoffAddress}',
      timeLabel: _formatTime(ride.createdAt),
      status: _rideStatusToTransaction(ride.status),
      createdAt: ride.createdAt,
      amountPesewas: ride.totalPaidPesewas ??
          ride.finalFarePesewas ??
          ride.estimatedFarePesewas,
    );
  }

  TransactionItem _jobJsonToTransaction(Map<String, dynamic> json) {
    final createdAt = json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now();
    final statusStr = json['status'] as String? ?? 'open';
    final description = json['description'] as String? ?? '';
    final category = json['category'] as Map<String, dynamic>?;
    final categoryName = category?['name'] as String? ?? 'Service';
    final addressText = json['addressText'] as String? ?? '';

    return TransactionItem(
      id: json['id'] as String? ?? '',
      type: TransactionType.job,
      title: description.length > 60
          ? '${description.substring(0, 60)}...'
          : description,
      locationLabel: addressText.isNotEmpty ? addressText : categoryName,
      timeLabel: _formatTime(createdAt),
      status: _jobStatusToTransaction(statusStr),
      createdAt: createdAt,
      // Tolerant of backend field-name drift — same set the payment summary
      // parser uses, plus the older `agreedPrice` / `budgetPesewas` shapes.
      // Reads as num so doubles-typed JSON values don't silently null out.
      amountPesewas: _firstNum(json, const [
            'agreedPricePesewas',
            'agreed_price_pesewas',
            'totalPesewas',
            'total_pesewas',
            'amountPesewas',
            'amount_pesewas',
            'agreedPrice',
            'budgetPesewas',
          ])?.toInt() ??
          0,
    );
  }

  /// First numeric (any [num]) value under [keys] in [node], or null.
  /// Reads `num` rather than `int` so JSON values that round-trip as
  /// `double` (e.g. `15000.0`) aren't dropped by a strict `as int?` cast.
  static num? _firstNum(Map<String, dynamic> node, List<String> keys) {
    for (final k in keys) {
      final v = node[k];
      if (v is num) return v;
    }
    return null;
  }

  TransactionStatus _rideStatusToTransaction(RideStatus status) {
    return switch (status) {
      RideStatus.completed => TransactionStatus.completed,
      RideStatus.cancelled => TransactionStatus.cancelled,
      RideStatus.inProgress => TransactionStatus.inProgress,
      _ => TransactionStatus.pending,
    };
  }

  TransactionStatus _jobStatusToTransaction(String status) {
    return switch (status) {
      'completed' => TransactionStatus.completed,
      'cancelled' => TransactionStatus.cancelled,
      'in_progress' ||
      'arrived' ||
      'artisan_en_route' ||
      'en_route' ||
      'artisan_marked_complete' =>
        TransactionStatus.inProgress,
      _ => TransactionStatus.pending,
    };
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final time = DateFormat.jm().format(dt);

    if (date == today) return time;
    return '${DateFormat.MMMd().format(dt)}, $time';
  }

  List<TransactionGroup> _groupByDate(List<TransactionItem> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeekStart = today.subtract(const Duration(days: 7));

    final todayItems = <TransactionItem>[];
    final yesterdayItems = <TransactionItem>[];
    final lastWeekItems = <TransactionItem>[];
    final olderItems = <TransactionItem>[];

    for (final item in items) {
      final date = DateTime(
          item.createdAt.year, item.createdAt.month, item.createdAt.day);
      if (date == today) {
        todayItems.add(item);
      } else if (date == yesterday) {
        yesterdayItems.add(item);
      } else if (date.isAfter(lastWeekStart)) {
        lastWeekItems.add(item);
      } else {
        olderItems.add(item);
      }
    }

    return [
      if (todayItems.isNotEmpty)
        TransactionGroup(label: 'TODAY', items: todayItems),
      if (yesterdayItems.isNotEmpty)
        TransactionGroup(label: 'YESTERDAY', items: yesterdayItems),
      if (lastWeekItems.isNotEmpty)
        TransactionGroup(label: 'LAST WEEK', items: lastWeekItems),
      if (olderItems.isNotEmpty)
        TransactionGroup(label: 'EARLIER', items: olderItems),
    ];
  }
}

final activityHistoryProvider = StateNotifierProvider.autoDispose<
    ActivityHistoryNotifier, ActivityHistoryState>(
  (ref) => ActivityHistoryNotifier(ref),
);

// ── Derived: filtered groups ──────────────────────────────────────────────────

final filteredActivityGroupsProvider =
    Provider.autoDispose<List<TransactionGroup>>((ref) {
  final state = ref.watch(activityHistoryProvider);
  final filter = state.filter;
  final query = state.searchQuery.trim().toLowerCase();

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
