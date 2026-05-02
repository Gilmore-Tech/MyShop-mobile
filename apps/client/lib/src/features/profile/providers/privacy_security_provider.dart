import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

// ── KYC Status ────────────────────────────────────────────────────────────────
// EDD § Verification Module: Smile Identity webhook drives this status.
// Clients are not required to verify at registration — KYC is optional but
// incentivised (ID Verified badge visible to artisans, higher transaction
// limits). PRD § 9.6 & edge case #4.

enum KycStatus { unverified, pending, verified, rejected }

/// Maps the backend's `client.kycStatus` string to the local enum.
/// Backend values: 'not_started' | 'pending_review' | 'verified' | 'rejected'.
KycStatus _kycStatusFromBackend(String? raw,
    {required bool ghanaCardVerified}) {
  if (ghanaCardVerified) return KycStatus.verified;
  return switch (raw) {
    'pending_review' => KycStatus.pending,
    'verified' => KycStatus.verified,
    'rejected' => KycStatus.rejected,
    _ => KycStatus.unverified,
  };
}

// ── Privacy & Security Data ───────────────────────────────────────────────────
// Aggregates fields shown on the Privacy & Security screen.
// Sourced from the live auth profile — no extra API call needed.

class PrivacySecurityData {
  final KycStatus kycStatus;

  // Masked per backend masking rules (EDD § Auth Module — phone masking).
  final String maskedPhone;

  // Ghana Card masked display: plaintext never exposed on client.
  // Backend stores AES-256 encrypted (EDD § 10.2). When the user has
  // submitted but not yet been approved, this shows "Under review".
  final String maskedNationalId;

  // Whether local biometric auth (FaceID / fingerprint) is active on this device.
  final String biometricLabel;

  /// Free-text reason supplied by the admin when [kycStatus] is rejected.
  /// Drives the inline error copy below the National ID row.
  final String? kycRejectionReason;

  const PrivacySecurityData({
    required this.kycStatus,
    required this.maskedPhone,
    required this.maskedNationalId,
    required this.biometricLabel,
    this.kycRejectionReason,
  });
}

// ── State ─────────────────────────────────────────────────────────────────────

class PrivacySecurityState {
  final PrivacySecurityData? data;
  final bool isLoading;
  final bool isDeletingAccount;

  /// True while the Ghana Card upload + submit chain is in flight. Drives
  /// the spinner on the submit sheet.
  final bool isSubmittingKyc;

  /// True once the account has been deleted server-side and local tokens
  /// have been cleared. The screen listens for this to navigate to auth.
  final bool isAccountDeleted;

  final String? errorMessage;

  const PrivacySecurityState({
    this.data,
    this.isLoading = true,
    this.isDeletingAccount = false,
    this.isSubmittingKyc = false,
    this.isAccountDeleted = false,
    this.errorMessage,
  });

  PrivacySecurityState copyWith({
    PrivacySecurityData? data,
    bool? isLoading,
    bool? isDeletingAccount,
    bool? isSubmittingKyc,
    bool? isAccountDeleted,
    String? errorMessage,
    bool clearError = false,
  }) =>
      PrivacySecurityState(
        data: data ?? this.data,
        isLoading: isLoading ?? this.isLoading,
        isDeletingAccount: isDeletingAccount ?? this.isDeletingAccount,
        isSubmittingKyc: isSubmittingKyc ?? this.isSubmittingKyc,
        isAccountDeleted: isAccountDeleted ?? this.isAccountDeleted,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PrivacySecurityNotifier extends StateNotifier<PrivacySecurityState> {
  PrivacySecurityNotifier(this._ref) : super(const PrivacySecurityState()) {
    _load();
  }

  final Ref _ref;

  /// Sources the displayed values from the live auth state instead of a
  /// dedicated /privacy endpoint — every field on this screen is already
  /// in the user profile we keep in [clientAuthControllerProvider]. This
  /// avoids a redundant network call and keeps the screen in sync with
  /// the rest of the app the moment the profile is refreshed.
  void _load() {
    final authState = _ref.read(clientAuthControllerProvider);
    if (authState is! AuthAuthenticated) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: "Couldn't load privacy details — please sign in again.",
      );
      return;
    }

    final profile = authState.profile;
    final client = profile.client;
    final kyc = _kycStatusFromBackend(
      client?.kycStatus,
      ghanaCardVerified: client?.ghanaCardVerified ?? false,
    );

    final nationalIdLabel = switch (kyc) {
      KycStatus.verified => 'GHA-•••••••••-•',
      KycStatus.pending => 'Under review',
      KycStatus.rejected => 'Rejected — re-submit',
      KycStatus.unverified => 'Not on file',
    };

    state = state.copyWith(
      isLoading: false,
      data: PrivacySecurityData(
        kycStatus: kyc,
        maskedPhone: _maskPhone(profile.phone),
        maskedNationalId: nationalIdLabel,
        kycRejectionReason: client?.kycRejectionReason,
        // Real biometric state lives in [biometricSettingProvider] once
        // that screen is built — surface a neutral fallback for now.
        biometricLabel: 'Tap to set up',
      ),
      clearError: true,
    );
  }

  /// End-to-end Ghana Card submission:
  ///   1. Upload [imageFile] via /media/upload-url + /media/confirm (purpose
  ///      'profile_photo' — the backend reuses that purpose for KYC images).
  ///   2. POST /users/me/ghana-card with the resulting URL + [cardNumber].
  ///   3. Refresh the auth profile so kycStatus flips to 'pending_review'
  ///      throughout the app.
  ///
  /// Returns `null` on success, a user-facing error message on failure.
  /// The card number is sent in the canonical `GHA-XXXXXXXXX-X` format —
  /// callers should validate before calling. This method does not retry; the
  /// sheet keeps the form open on failure so the user can fix and re-submit.
  Future<String?> submitGhanaCard({
    required File imageFile,
    required String cardNumber,
  }) async {
    if (state.isSubmittingKyc) return null;
    state = state.copyWith(isSubmittingKyc: true, clearError: true);

    String hostedUrl;
    try {
      hostedUrl = await _ref
          .read(mediaServiceProvider)
          .uploadProfilePhoto(imageFile.path);
    } on ApiException catch (e) {
      state = state.copyWith(isSubmittingKyc: false);
      return e.message.isNotEmpty
          ? e.message
          : "Couldn't upload the Ghana Card image. Please try again.";
    } catch (_) {
      state = state.copyWith(isSubmittingKyc: false);
      return "Couldn't upload the Ghana Card image. Please try again.";
    }

    try {
      await _ref.read(userServiceProvider).submitClientGhanaCard(
            documentImageUrl: hostedUrl,
            ghanaCardNumber: cardNumber,
          );
    } on ApiException catch (e) {
      state = state.copyWith(isSubmittingKyc: false);
      return _friendlySubmitError(e);
    } catch (_) {
      state = state.copyWith(isSubmittingKyc: false);
      return "Couldn't submit your Ghana Card. Please try again.";
    }

    // Pull the updated profile so kycStatus flows through to every screen.
    await _ref.read(clientAuthControllerProvider.notifier).refreshProfile();
    if (!mounted) return null;
    _load();
    state = state.copyWith(isSubmittingKyc: false);
    return null;
  }

  String _friendlySubmitError(ApiException e) {
    switch (e.errorCode) {
      case 'INVALID_GHANA_CARD_NUMBER':
        return 'That Ghana Card number doesn\'t match the GHA-XXXXXXXXX-X '
            'format. Double-check and try again.';
      case 'KYC_IN_PROGRESS':
        return 'Your previous submission is still under review. We\'ll let '
            "you know once it's approved.";
      case 'KYC_ALREADY_VERIFIED':
        return 'Your Ghana Card is already verified.';
      case 'CLIENT_PROFILE_REQUIRED':
        return "This account isn't set up as a client. Contact support.";
      default:
        return e.message.isNotEmpty
            ? e.message
            : "Couldn't submit your Ghana Card. Please try again.";
    }
  }

  Future<void> reload() async {
    state = state.copyWith(isLoading: true, clearError: true);
    _load();
  }

  /// Permanently deletes the account.
  /// DELETE /v1/users/me. On success clears local tokens and flips
  /// [PrivacySecurityState.isAccountDeleted] to true; the calling screen
  /// listens for that to route the user to the auth screen.
  ///
  /// Backend is responsible for any soft-delete / retention logic; from
  /// the client's perspective once 200 lands the session is over.
  Future<void> deleteAccount() async {
    if (state.isDeletingAccount) return;
    state = state.copyWith(isDeletingAccount: true, clearError: true);

    try {
      await _ref.read(userServiceProvider).deleteAccount();
    } on ApiException catch (e) {
      state = state.copyWith(
        isDeletingAccount: false,
        errorMessage: e.message.isNotEmpty
            ? e.message
            : "Couldn't delete your account. Please try again.",
      );
      return;
    } catch (_) {
      state = state.copyWith(
        isDeletingAccount: false,
        errorMessage: "Couldn't delete your account. Please try again.",
      );
      return;
    }

    // Server-side gone. Clear tokens + flip auth state to unauthenticated
    // so the router redirect drops the user back to the auth screen.
    await _ref.read(clientAuthControllerProvider.notifier).logout();
    if (!mounted) return;
    state = state.copyWith(
      isDeletingAccount: false,
      isAccountDeleted: true,
    );
  }

  /// Masks all but the last 4 digits of a phone number.
  /// "+233244987654" → "+233 *** *** 7654"
  static String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length < 4) return phone;
    final last4 = digits.substring(digits.length - 4);
    final prefix = digits.startsWith('+') ? '+233' : '0';
    return '$prefix *** *** $last4';
  }
}

final privacySecurityProvider = StateNotifierProvider.autoDispose<
    PrivacySecurityNotifier, PrivacySecurityState>(
  (ref) => PrivacySecurityNotifier(ref),
);
