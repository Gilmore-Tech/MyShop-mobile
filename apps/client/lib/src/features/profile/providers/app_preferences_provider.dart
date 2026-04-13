import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme_provider.dart';

// ── Distance Unit ─────────────────────────────────────────────────────────────

enum DistanceUnit { km, miles }

extension DistanceUnitX on DistanceUnit {
  String get label => switch (this) {
        DistanceUnit.km    => 'KM',
        DistanceUnit.miles => 'Miles',
      };
}

// ── App Theme ─────────────────────────────────────────────────────────────────

enum AppThemeMode { light, dark }

extension AppThemeModeX on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.light => 'Light',
        AppThemeMode.dark  => 'Dark',
      };
}

// ── Language Option ───────────────────────────────────────────────────────────
// PRD § 11 Localisation: English + Twi at launch. Further languages post-pilot.
// EDD § 13 L10n: language_code stored on user profile, synced via PUT /v1/users/me.

class LanguageOption {
  final String code;
  final String label;
  final bool   isSystemDefault;

  const LanguageOption({
    required this.code,
    required this.label,
    required this.isSystemDefault,
  });
}

const kSupportedLanguages = <LanguageOption>[
  LanguageOption(code: 'en_US', label: 'English (US)',  isSystemDefault: true),
  LanguageOption(code: 'tw',    label: 'Twi (Asante)',  isSystemDefault: false),
];

// ── State ─────────────────────────────────────────────────────────────────────
// API: PUT /v1/users/me  { distanceUnit, languageCode, theme,
//                          replayOnboarding, featureUpdates }

class AppPreferencesState {
  final DistanceUnit   distanceUnit;
  final String         languageCode;
  final AppThemeMode   themeMode;
  final bool           replayOnboarding;
  final bool           featureUpdates;

  // ── Async ──
  final bool    isSaving;
  final bool    isSaved;
  final String? errorMessage;

  const AppPreferencesState({
    this.distanceUnit    = DistanceUnit.km,
    this.languageCode    = 'en_US',
    this.themeMode       = AppThemeMode.light,
    this.replayOnboarding = false,
    this.featureUpdates  = true,
    this.isSaving        = false,
    this.isSaved         = false,
    this.errorMessage,
  });

  LanguageOption get selectedLanguage =>
      kSupportedLanguages.firstWhere(
        (l) => l.code == languageCode,
        orElse: () => kSupportedLanguages.first,
      );

  AppPreferencesState copyWith({
    DistanceUnit?  distanceUnit,
    String?        languageCode,
    AppThemeMode?  themeMode,
    bool?          replayOnboarding,
    bool?          featureUpdates,
    bool?          isSaving,
    bool?          isSaved,
    String?        errorMessage,
    bool           clearError = false,
  }) =>
      AppPreferencesState(
        distanceUnit:    distanceUnit    ?? this.distanceUnit,
        languageCode:    languageCode    ?? this.languageCode,
        themeMode:       themeMode       ?? this.themeMode,
        replayOnboarding: replayOnboarding ?? this.replayOnboarding,
        featureUpdates:  featureUpdates  ?? this.featureUpdates,
        isSaving:        isSaving        ?? this.isSaving,
        isSaved:         isSaved         ?? this.isSaved,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AppPreferencesNotifier extends StateNotifier<AppPreferencesState> {
  AppPreferencesNotifier(this._ref) : super(const AppPreferencesState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    // Sync initial theme from the persisted ThemeNotifier (SharedPreferences).
    final currentTheme = _ref.read(themeNotifierProvider);
    final initialThemeMode =
        currentTheme == ThemeMode.dark ? AppThemeMode.dark : AppThemeMode.light;

    // TODO: GET /v1/users/me — populate distanceUnit, languageCode, theme, etc.
    await Future.delayed(const Duration(milliseconds: 200));
    state = state.copyWith(
      distanceUnit:     DistanceUnit.km,
      languageCode:     'en_US',
      themeMode:        initialThemeMode,
      replayOnboarding: false,
      featureUpdates:   true,
    );
  }

  void setDistanceUnit(DistanceUnit v) =>
      state = state.copyWith(distanceUnit: v, isSaved: false, clearError: true);

  void setLanguage(String code) =>
      state = state.copyWith(languageCode: code, isSaved: false, clearError: true);

  void setTheme(AppThemeMode v) {
    state = state.copyWith(themeMode: v, isSaved: false, clearError: true);
    _ref.read(themeNotifierProvider.notifier).setMode(
          v == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.light,
        );
  }

  void toggleReplayOnboarding(bool v) =>
      state = state.copyWith(replayOnboarding: v, isSaved: false, clearError: true);

  void toggleFeatureUpdates(bool v) =>
      state = state.copyWith(featureUpdates: v, isSaved: false, clearError: true);

  /// Persists all preferences.
  /// PUT /v1/users/me { distanceUnit, languageCode, theme, replayOnboarding,
  ///                    featureUpdates }
  Future<void> savePreferences() async {
    if (state.isSaving) return;
    state = state.copyWith(isSaving: true, clearError: true);
    // TODO: PUT /v1/users/me with preferences payload
    await Future.delayed(const Duration(milliseconds: 700));
    state = state.copyWith(isSaving: false, isSaved: true);
    // Reset "Saved" indicator after 2 seconds
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) state = state.copyWith(isSaved: false);
  }
}

final appPreferencesProvider = StateNotifierProvider.autoDispose<
    AppPreferencesNotifier, AppPreferencesState>(
  (ref) => AppPreferencesNotifier(ref),
);
