import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme_provider.dart';

// ── SharedPreferences keys ────────────────────────────────────────────────────
// Theme is owned by [themeNotifierProvider] under its own key — these are
// for the prefs that don't have a dedicated provider yet.

const _kPrefDistanceUnit = 'app_pref_distance_unit'; // 'km' | 'miles'
const _kPrefReplayOnboarding = 'app_pref_replay_onboarding'; // bool
const _kPrefFeatureUpdates = 'app_pref_feature_updates'; // bool

// ── Distance Unit ─────────────────────────────────────────────────────────────

enum DistanceUnit { km, miles }

extension DistanceUnitX on DistanceUnit {
  String get label => switch (this) {
        DistanceUnit.km => 'KM',
        DistanceUnit.miles => 'Miles',
      };
}

// ── App Theme ─────────────────────────────────────────────────────────────────

enum AppThemeMode { light, dark }

extension AppThemeModeX on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
      };
}

// ── State ─────────────────────────────────────────────────────────────────────

class AppPreferencesState {
  final DistanceUnit distanceUnit;
  final AppThemeMode themeMode;
  final bool replayOnboarding;
  final bool featureUpdates;

  /// Reserved for future failures from auto-save side effects. Currently
  /// every pref is a SharedPreferences write that doesn't 4xx, so this is
  /// always null — kept on the state to avoid churn if a backend-backed
  /// pref is added later.
  final String? errorMessage;

  const AppPreferencesState({
    this.distanceUnit = DistanceUnit.km,
    this.themeMode = AppThemeMode.light,
    this.replayOnboarding = false,
    this.featureUpdates = true,
    this.errorMessage,
  });

  AppPreferencesState copyWith({
    DistanceUnit? distanceUnit,
    AppThemeMode? themeMode,
    bool? replayOnboarding,
    bool? featureUpdates,
    String? errorMessage,
    bool clearError = false,
  }) =>
      AppPreferencesState(
        distanceUnit: distanceUnit ?? this.distanceUnit,
        themeMode: themeMode ?? this.themeMode,
        replayOnboarding: replayOnboarding ?? this.replayOnboarding,
        featureUpdates: featureUpdates ?? this.featureUpdates,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AppPreferencesNotifier extends StateNotifier<AppPreferencesState> {
  AppPreferencesNotifier(this._ref) : super(const AppPreferencesState()) {
    _load();
  }

  final Ref _ref;

  /// Auto-save model:
  ///   - Theme       → owned by themeNotifierProvider, persists immediately.
  ///   - Distance / replay-onboarding / feature-updates → SharedPreferences,
  ///     persists immediately (the writes are awaited but UI doesn't block).
  /// There's no explicit "Save" button — every selection sticks the moment
  /// the user taps it.
  Future<void> _load() async {
    // Sync theme from persisted ThemeNotifier (its own SharedPreferences key).
    final currentTheme = _ref.read(themeNotifierProvider);
    final initialThemeMode =
        currentTheme == ThemeMode.dark ? AppThemeMode.dark : AppThemeMode.light;

    // Hydrate the local-only prefs from SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final initialDistanceUnit = prefs.getString(_kPrefDistanceUnit) == 'miles'
        ? DistanceUnit.miles
        : DistanceUnit.km;
    final initialReplayOnboarding =
        prefs.getBool(_kPrefReplayOnboarding) ?? false;
    final initialFeatureUpdates = prefs.getBool(_kPrefFeatureUpdates) ?? true;

    if (!mounted) return;
    state = state.copyWith(
      themeMode: initialThemeMode,
      distanceUnit: initialDistanceUnit,
      replayOnboarding: initialReplayOnboarding,
      featureUpdates: initialFeatureUpdates,
    );
  }

  Future<void> setDistanceUnit(DistanceUnit v) async {
    state = state.copyWith(distanceUnit: v, clearError: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefDistanceUnit,
      v == DistanceUnit.miles ? 'miles' : 'km',
    );
  }

  void setTheme(AppThemeMode v) {
    state = state.copyWith(themeMode: v, clearError: true);
    _ref.read(themeNotifierProvider.notifier).setMode(
          v == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.light,
        );
  }

  Future<void> toggleReplayOnboarding(bool v) async {
    state = state.copyWith(replayOnboarding: v, clearError: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefReplayOnboarding, v);
  }

  Future<void> toggleFeatureUpdates(bool v) async {
    state = state.copyWith(featureUpdates: v, clearError: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefFeatureUpdates, v);
  }
}

final appPreferencesProvider = StateNotifierProvider.autoDispose<
    AppPreferencesNotifier, AppPreferencesState>(
  (ref) => AppPreferencesNotifier(ref),
);
