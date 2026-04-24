import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Promo Frequency ───────────────────────────────────────────────────────────

enum PromoFrequency { daily, weekly, minimal }

extension PromoFrequencyX on PromoFrequency {
  String get label => switch (this) {
        PromoFrequency.daily   => 'Daily',
        PromoFrequency.weekly  => 'Weekly',
        PromoFrequency.minimal => 'Minimal',
      };

  String get apiValue => switch (this) {
        PromoFrequency.daily   => 'daily',
        PromoFrequency.weekly  => 'weekly',
        PromoFrequency.minimal => 'minimal',
      };
}

PromoFrequency _parseFrequency(String? raw) => switch (raw) {
      'weekly'  => PromoFrequency.weekly,
      'minimal' => PromoFrequency.minimal,
      _         => PromoFrequency.daily,
    };

// ── State ─────────────────────────────────────────────────────────────────────

class NotificationSettingsState {
  final bool pushEnabled;
  final bool smsEnabled;
  final bool emailEnabled;
  final bool criticalSafetyEnabled;
  final PromoFrequency promoFrequency;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  const NotificationSettingsState({
    this.pushEnabled           = true,
    this.smsEnabled            = false,
    this.emailEnabled          = true,
    this.criticalSafetyEnabled = true,
    this.promoFrequency        = PromoFrequency.daily,
    this.isLoading             = false,
    this.isSaving              = false,
    this.errorMessage,
  });

  NotificationSettingsState copyWith({
    bool?            pushEnabled,
    bool?            smsEnabled,
    bool?            emailEnabled,
    bool?            criticalSafetyEnabled,
    PromoFrequency?  promoFrequency,
    bool?            isLoading,
    bool?            isSaving,
    String?          errorMessage,
    bool             clearError = false,
  }) =>
      NotificationSettingsState(
        pushEnabled:           pushEnabled           ?? this.pushEnabled,
        smsEnabled:            smsEnabled            ?? this.smsEnabled,
        emailEnabled:          emailEnabled          ?? this.emailEnabled,
        criticalSafetyEnabled: criticalSafetyEnabled ?? this.criticalSafetyEnabled,
        promoFrequency:        promoFrequency        ?? this.promoFrequency,
        isLoading:             isLoading             ?? this.isLoading,
        isSaving:              isSaving              ?? this.isSaving,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotificationSettingsNotifier
    extends StateNotifier<NotificationSettingsState> {
  NotificationSettingsNotifier(this._ref)
      : super(const NotificationSettingsState()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prefs =
          await _ref.read(userServiceProvider).getNotificationPreferences();
      state = state.copyWith(
        isLoading:             false,
        pushEnabled:           prefs['pushEnabled']           as bool? ?? true,
        smsEnabled:            prefs['smsEnabled']            as bool? ?? false,
        emailEnabled:          prefs['emailEnabled']          as bool? ?? true,
        criticalSafetyEnabled: prefs['criticalSafetyEnabled'] as bool? ?? true,
        promoFrequency: _parseFrequency(prefs['promoFrequency'] as String?),
      );
    } catch (e) {
      developer.log(
          'getNotificationPreferences error: $e', name: 'NotificationSettings');
      // Keep defaults on failure — non-fatal since toggles still work.
      state = state.copyWith(isLoading: false);
    }
  }

  void togglePush(bool v) =>
      _save(state.copyWith(pushEnabled: v, clearError: true));

  void toggleSms(bool v) =>
      _save(state.copyWith(smsEnabled: v, clearError: true));

  void toggleEmail(bool v) =>
      _save(state.copyWith(emailEnabled: v, clearError: true));

  void toggleCriticalSafety(bool v) =>
      _save(state.copyWith(criticalSafetyEnabled: v, clearError: true));

  void setPromoFrequency(PromoFrequency f) =>
      _save(state.copyWith(promoFrequency: f, clearError: true));

  /// Optimistic save — UI updates immediately, API call happens in background.
  Future<void> _save(NotificationSettingsState next) async {
    if (state.isSaving) return;
    final previous = state;
    state = next.copyWith(isSaving: true);
    try {
      await _ref.read(userServiceProvider).updateNotificationPreferences(
            pushEnabled:           next.pushEnabled,
            smsEnabled:            next.smsEnabled,
            emailEnabled:          next.emailEnabled,
            criticalSafetyEnabled: next.criticalSafetyEnabled,
            promoFrequency:        next.promoFrequency.apiValue,
          );
      state = state.copyWith(isSaving: false);
    } catch (e) {
      developer.log(
          'updateNotificationPreferences error: $e', name: 'NotificationSettings');
      // Roll back to previous state on failure.
      state = previous.copyWith(
        isSaving:     false,
        errorMessage: 'Could not save settings. Please try again.',
      );
    }
  }

  Future<void> sendTestNotification() async {
    // Stub — POST /notifications/test not yet implemented on backend.
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

final notificationSettingsProvider = StateNotifierProvider.autoDispose<
    NotificationSettingsNotifier, NotificationSettingsState>(
  (ref) => NotificationSettingsNotifier(ref),
);
