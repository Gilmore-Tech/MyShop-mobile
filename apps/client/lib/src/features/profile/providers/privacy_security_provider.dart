import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── KYC Status ────────────────────────────────────────────────────────────────
// EDD § Verification Module: Smile Identity webhook drives this status.
// Clients are not required to verify at registration — KYC is optional but
// incentivised (ID Verified badge visible to artisans, higher transaction
// limits). PRD § 9.6 & edge case #4.

enum KycStatus { unverified, pending, verified, rejected }

// ── Privacy & Security Data ───────────────────────────────────────────────────
// Aggregates fields shown on the Privacy & Security screen.
// Loaded from GET /v1/users/me + GET /v1/verification/status.

class PrivacySecurityData {
  final KycStatus kycStatus;

  // Masked per backend masking rules (EDD § Auth Module — phone masking).
  final String maskedPhone;

  // Ghana Card masked display: "GHA_____x" — plaintext never exposed on client.
  // Backend returns pre-masked form; AES-256 encrypted at rest (EDD § 10.2).
  final String maskedNationalId;

  // Whether local biometric auth (FaceID / fingerprint) is active on this device.
  final String biometricLabel;

  const PrivacySecurityData({
    required this.kycStatus,
    required this.maskedPhone,
    required this.maskedNationalId,
    required this.biometricLabel,
  });
}

// ── State ─────────────────────────────────────────────────────────────────────

class PrivacySecurityState {
  final PrivacySecurityData? data;
  final bool isLoading;
  final bool isDeletingAccount;
  final String? errorMessage;

  const PrivacySecurityState({
    this.data,
    this.isLoading       = true,
    this.isDeletingAccount = false,
    this.errorMessage,
  });

  PrivacySecurityState copyWith({
    PrivacySecurityData? data,
    bool?   isLoading,
    bool?   isDeletingAccount,
    String? errorMessage,
    bool    clearError = false,
  }) =>
      PrivacySecurityState(
        data:              data              ?? this.data,
        isLoading:         isLoading         ?? this.isLoading,
        isDeletingAccount: isDeletingAccount ?? this.isDeletingAccount,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PrivacySecurityNotifier extends StateNotifier<PrivacySecurityState> {
  PrivacySecurityNotifier() : super(const PrivacySecurityState()) {
    _load();
  }

  Future<void> _load() async {
    // TODO: GET /v1/users/me + GET /v1/verification/status
    await Future.delayed(const Duration(milliseconds: 250));
    state = state.copyWith(
      isLoading: false,
      data: const PrivacySecurityData(
        kycStatus:       KycStatus.verified,
        maskedPhone:     '+233 *** *** 4582',
        maskedNationalId: 'GHA_____x',
        biometricLabel:  'FaceID / Fingerprint Active',
      ),
    );
  }

  Future<void> reload() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _load();
  }

  /// Soft-deletes the account. Data retained 90 days; 24h recovery window.
  /// DELETE /v1/users/me  (EDD § User Module — soft delete via deleted_at).
  /// Blocked if provider has outstanding clawback balance (PRD edge case #51).
  Future<void> deleteAccount() async {
    if (state.isDeletingAccount) return;
    state = state.copyWith(isDeletingAccount: true, clearError: true);
    // TODO: DELETE /v1/users/me
    // On success: clear JWT tokens, navigate to login screen.
    await Future.delayed(const Duration(milliseconds: 900));
    state = state.copyWith(isDeletingAccount: false);
  }
}

final privacySecurityProvider =
    StateNotifierProvider.autoDispose<PrivacySecurityNotifier, PrivacySecurityState>(
  (_) => PrivacySecurityNotifier(),
);
