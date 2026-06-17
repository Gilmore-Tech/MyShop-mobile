import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/loyalty_models.dart';
import 'loyalty_redemption_providers.dart';

/// Immutable view-state for the paginated points-history screen.
class PointsHistoryState {
  const PointsHistoryState({
    this.items = const [],
    this.page = 0,
    this.totalPages = 1,
    this.isLoadingInitial = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<LoyaltyTransaction> items;
  final int page;
  final int totalPages;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => page < totalPages;
  bool get isEmpty => items.isEmpty;

  PointsHistoryState copyWith({
    List<LoyaltyTransaction>? items,
    int? page,
    int? totalPages,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return PointsHistoryState(
      items: items ?? this.items,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads `/loyalty/transactions` page-by-page, appending as the user scrolls.
class PointsHistoryController extends StateNotifier<PointsHistoryState> {
  PointsHistoryController(this._ref) : super(const PointsHistoryState()) {
    refresh();
  }

  final Ref _ref;
  static const _limit = 20;

  Future<void> refresh() async {
    state = const PointsHistoryState(isLoadingInitial: true);
    try {
      final page = await _ref
          .read(loyaltyRepositoryProvider)
          .fetchTransactions(page: 1, limit: _limit);
      state = PointsHistoryState(
        items: page.items,
        page: page.page,
        totalPages: page.totalPages,
        isLoadingInitial: false,
      );
    } catch (e) {
      state = PointsHistoryState(isLoadingInitial: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoadingInitial || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final next = await _ref
          .read(loyaltyRepositoryProvider)
          .fetchTransactions(page: state.page + 1, limit: _limit);
      state = state.copyWith(
        items: [...state.items, ...next.items],
        page: next.page,
        totalPages: next.totalPages,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }
}

final pointsHistoryProvider = StateNotifierProvider.autoDispose<
    PointsHistoryController, PointsHistoryState>((ref) {
  return PointsHistoryController(ref);
});
