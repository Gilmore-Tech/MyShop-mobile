import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Promo Frequency ───────────────────────────────────────────────────────────
// PRD § 10 Notification Strategy: promotional frequency is user-configurable.

enum PromoFrequency { daily, weekly, minimal }

extension PromoFrequencyX on PromoFrequency {
  String get label => switch (this) {
        PromoFrequency.daily   => 'Daily',
        PromoFrequency.weekly  => 'Weekly',
        PromoFrequency.minimal => 'Minimal',
      };
}

// ── State ─────────────────────────────────────────────────────────────────────
// API: GET  /v1/users/me/notification-preferences
//      PATCH /v1/users/me/notification-preferences

class NotificationSettingsState {
  // ── Delivery channels ──
  final bool pushEnabled;
  final bool smsEnabled;
  final bool emailEnabled;

  // ── Content & frequency ──
  // criticalSafetyEnabled maps to PRD § 10 "Emergency Broadcasting" channel.
  // The backend sends emergency alerts regardless; this toggle controls
  // whether the OS can silence them (i.e. critical-alert entitlement on iOS,
  // high-priority FCM on Android).
  final bool criticalSafetyEnabled;
  final PromoFrequency promoFrequency;

  // ── Async ──
  final bool isSaving;
  final String? errorMessage;

  const NotificationSettingsState({
    this.pushEnabled         = true,
    this.smsEnabled          = false,
    this.emailEnabled        = true,
    this.criticalSafetyEnabled = true,
    this.promoFrequency      = PromoFrequency.daily,
    this.isSaving            = false,
    this.errorMessage,
  });

  NotificationSettingsState copyWith({
    bool?            pushEnabled,
    bool?            smsEnabled,
    bool?            emailEnabled,
    bool?            criticalSafetyEnabled,
    PromoFrequency?  promoFrequency,
    bool?            isSaving,
    String?          errorMessage,
    bool             clearError = false,
  }) =>
      NotificationSettingsState(
        pushEnabled:           pushEnabled          ?? this.pushEnabled,
        smsEnabled:            smsEnabled           ?? this.smsEnabled,
        emailEnabled:          emailEnabled         ?? this.emailEnabled,
        criticalSafetyEnabled: criticalSafetyEnabled ?? this.criticalSafetyEnabled,
        promoFrequency:        promoFrequency       ?? this.promoFrequency,
        isSaving:              isSaving             ?? this.isSaving,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotificationSettingsNotifier
    extends StateNotifier<NotificationSettingsState> {
  NotificationSettingsNotifier() : super(const NotificationSettingsState()) {
    _load();
  }

  Future<void> _load() async {
    // TODO: GET /v1/users/me/notification-preferences
    await Future.delayed(const Duration(milliseconds: 200));
    // Mock matches design screenshot defaults.
    state = state.copyWith(
      pushEnabled:           true,
      smsEnabled:            false,
      emailEnabled:          true,
      criticalSafetyEnabled: true,
      promoFrequency:        PromoFrequency.daily,
    );
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

  /// Optimistic save — applies UI change immediately, persists in background.
  /// PATCH /v1/users/me/notification-preferences
  Future<void> _save(NotificationSettingsState next) async {
    if (state.isSaving) return;
    state = next.copyWith(isSaving: true);
    // TODO: PATCH /v1/users/me/notification-preferences
    await Future.delayed(const Duration(milliseconds: 400));
    state = state.copyWith(isSaving: false);
  }

  /// POST /v1/notifications/test — triggers a sample notification.
  Future<void> sendTestNotification() async {
    // TODO: POST /v1/notifications/test
    await Future.delayed(const Duration(milliseconds: 600));
  }
}

final notificationSettingsProvider = StateNotifierProvider.autoDispose<
    NotificationSettingsNotifier, NotificationSettingsState>(
  (_) => NotificationSettingsNotifier(),
);
