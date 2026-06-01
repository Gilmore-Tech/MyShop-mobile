import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks unread / unseen counts for the bottom navigation tabs.
///
/// Each tab is keyed by its route path (`/home`, `/earnings`, `/trips`,
/// `/account`). When the user navigates to a tab the badge is cleared.
/// External data sources (WebSocket events, push notifications, API polls)
/// can push new counts via [increment] or [set].
class NavBadgeNotifier extends StateNotifier<Map<String, int>> {
  NavBadgeNotifier() : super(const {});

  /// Set the badge count for [tabPath] to an exact value.
  void set(String tabPath, int count) {
    if (count <= 0) {
      state = Map.of(state)..remove(tabPath);
    } else {
      state = {...state, tabPath: count};
    }
  }

  /// Add [delta] to the existing badge count (defaults to +1).
  void increment(String tabPath, [int delta = 1]) {
    final current = state[tabPath] ?? 0;
    set(tabPath, current + delta);
  }

  /// Clear the badge for [tabPath] (e.g. when the user opens that tab).
  void clear(String tabPath) {
    if (!state.containsKey(tabPath)) return;
    state = Map.of(state)..remove(tabPath);
  }
}

final navBadgeProvider =
    StateNotifierProvider<NavBadgeNotifier, Map<String, int>>(
  (_) => NavBadgeNotifier(),
);
