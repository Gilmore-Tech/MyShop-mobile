import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  bool get canSave => !isSaving && !isSaved;

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
      state = state.copyWith(
        fullName: profile.fullName,
        email: profile.email ?? '',
        phoneNumber: profile.phone,
        ghanaCardVerified: profile.client?.ghanaCardVerified ?? false,
        avatarUrl: profile.client?.profilePhotoUrl,
        originalEmail: profile.email ?? '',
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
