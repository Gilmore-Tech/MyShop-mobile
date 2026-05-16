import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart' show Validators;

import '../../auth/providers/auth_controller.dart';

// ── Edit Profile State ────────────────────────────────────────────────────────
// API: PUT /users/me  { fullName?, email? }
//
// Security rules (EDD § Auth / § Data Encryption):
//   - Changing email triggers OTP verification before the change is persisted.
//   - Phone number changes require a separate OTP flow — not handled here.
//   - Ghana Card is verified in the KYC flow — not editable here.

class EditProfileState {
  final String fullName;
  final String email;
  final String phoneNumber;
  final bool ghanaCardVerified;
  final String? avatarUrl;
  final String originalEmail;
  final bool isSaving;
  final bool isSaved;
  final String? errorMessage;

  const EditProfileState({
    this.fullName = '',
    this.email = '',
    this.phoneNumber = '',
    this.ghanaCardVerified = false,
    this.avatarUrl,
    this.originalEmail = '',
    this.isSaving = false,
    this.isSaved = false,
    this.errorMessage,
  });

  bool get emailChanged =>
      email.isNotEmpty && email.trim() != originalEmail.trim();

  /// Inline validation errors surfaced under each field. Both are optional
  /// from the API's perspective, so an empty field is fine — only a NON-
  /// empty value with a bad shape blocks save.
  String? get nameError {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return null;
    return Validators.fullName(trimmed);
  }

  String? get emailError {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return null;
    return Validators.email(trimmed);
  }

  bool get canSave =>
      !isSaving &&
      !isSaved &&
      nameError == null &&
      emailError == null;

  EditProfileState copyWith({
    String? fullName,
    String? email,
    String? phoneNumber,
    bool? ghanaCardVerified,
    String? avatarUrl,
    String? originalEmail,
    bool? isSaving,
    bool? isSaved,
    String? errorMessage,
    bool clearError = false,
  }) =>
      EditProfileState(
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        ghanaCardVerified: ghanaCardVerified ?? this.ghanaCardVerified,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        originalEmail: originalEmail ?? this.originalEmail,
        isSaving: isSaving ?? this.isSaving,
        isSaved: isSaved ?? this.isSaved,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class EditProfileNotifier extends StateNotifier<EditProfileState> {
  EditProfileNotifier(this._authController) : super(const EditProfileState()) {
    _loadProfile();
  }

  final ClientAuthController _authController;

  void _loadProfile() {
    final authState = _authController.state;
    if (authState is AuthAuthenticated) {
      final profile = authState.profile;
      // Phase 3 strict separation (CLAUDE.md §1, §8): the Client app
      // shows the Client role's profile, NOT the human's shared one.
      // Reading the root `users.email` is the cross-role bleed bug — a
      // user who registered Driver with email then Client without one
      // used to see the Driver's email here. We deliberately do NOT
      // fall back to root values. Null = user has not set an email
      // for the Client role; the field stays empty.
      final client = profile.client;
      state = state.copyWith(
        fullName: client?.legalName ?? profile.fullName,
        email: client?.email ?? '',
        phoneNumber: profile.phone,
        ghanaCardVerified: client?.ghanaCardVerified ?? false,
        avatarUrl: client?.profilePhotoUrl,
        originalEmail: client?.email ?? '',
      );
    }
  }

  void updateFullName(String v) =>
      state = state.copyWith(fullName: v, clearError: true);

  void updateEmail(String v) =>
      state = state.copyWith(email: v, clearError: true);

  /// PUT /users/me — saves full name and (if changed) email.
  Future<void> saveChanges() async {
    if (!state.canSave) return;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final error = await _authController.updateProfile(
        UpdateProfileRequest(
          fullName:
              state.fullName.trim().isNotEmpty ? state.fullName.trim() : null,
          email: state.emailChanged ? state.email.trim() : null,
        ),
      );
      if (error != null) {
        state = state.copyWith(isSaving: false, errorMessage: error);
      } else {
        state = state.copyWith(isSaving: false, isSaved: true);
        // Reset "Saved" indicator after 2 s so user can edit again.
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) state = state.copyWith(isSaved: false);
      }
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save. Please try again.',
      );
    }
  }
}

final editProfileProvider =
    StateNotifierProvider.autoDispose<EditProfileNotifier, EditProfileState>(
  (ref) => EditProfileNotifier(
    ref.watch(clientAuthControllerProvider.notifier),
  ),
);
