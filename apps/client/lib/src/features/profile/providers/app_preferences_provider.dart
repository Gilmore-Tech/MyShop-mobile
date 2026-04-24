import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme_provider.dart';
import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

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

// Maps the app-local language code to the backend languagePref value.
String _toBackendLang(String appCode) =>
    appCode == 'en_US' ? 'en' : appCode;

// Maps the backend languagePref value to the app-local language code.
String _fromBackendLang(String backendCode) =>
    backendCode == 'en' ? 'en_US' : backendCode;

// ── State ─────────────────────────────────────────────────────────────────────

class AppPreferencesState {
  final DistanceUnit   distanceUnit;
  final String         languageCode;
  final AppThemeMode   themeMode;
  final bool           replayOnboarding;
  final bool           featureUpdates;
  final bool           isSaving;
  final bool           isSaved;
  final String?        errorMessage;

  const AppPreferencesState({
    this.distanceUnit     = DistanceUnit.km,
    this.languageCode     = 'en_US',
    this.themeMode        = AppThemeMode.light,
    this.replayOnboarding = false,
    this.featureUpdates   = true,
    this.isSaving         = false,
    this.isSaved          = false,
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
        distanceUnit:     distanceUnit     ?? this.distanceUnit,
        languageCode:     languageCode     ?? this.languageCode,
        themeMode:        themeMode        ?? this.themeMode,
        replayOnboarding: replayOnboarding ?? this.replayOnboarding,
        featureUpdates:   featureUpdates   ?? this.featureUpdates,
        isSaving:         isSaving         ?? this.isSaving,
        isSaved:          isSaved          ?? this.isSaved,
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

  void _load() {
    // Sync theme from persisted ThemeNotifier (SharedPreferences).
    final currentTheme = _ref.read(themeNotifierProvider);
    final initialThemeMode =
        currentTheme == ThemeMode.dark ? AppThemeMode.dark : AppThemeMode.light;

    // Seed language from the authenticated user profile (already in memory).
    final authState = _ref.read(clientAuthControllerProvider);
    String initialLanguageCode = 'en_US';
    if (authState is AuthAuthenticated) {
      initialLanguageCode =
          _fromBackendLang(authState.profile.languagePref);
    }

    state = state.copyWith(
      themeMode:    initialThemeMode,
      languageCode: initialLanguageCode,
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

  /// Persists language preference to the backend; other prefs are local-only.
  Future<void> savePreferences() async {
    if (state.isSaving) return;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _ref.read(userServiceProvider).updateProfile(
            languagePref: _toBackendLang(state.languageCode),
          );
      state = state.copyWith(isSaving: false, isSaved: true);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) state = state.copyWith(isSaved: false);
    } catch (e) {
      developer.log('updateProfile (preferences) error: $e', name: 'AppPreferences');
      state = state.copyWith(
        isSaving:     false,
        errorMessage: 'Could not save preferences. Please try again.',
      );
    }
  }
}

final appPreferencesProvider = StateNotifierProvider.autoDispose<
    AppPreferencesNotifier, AppPreferencesState>(
  (ref) => AppPreferencesNotifier(ref),
);
