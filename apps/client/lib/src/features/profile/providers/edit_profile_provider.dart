import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_controller.dart';

// ── Edit Profile State ────────────────────────────────────────────────────────
// API: PUT /v1/users/me
//   { fullName?, email?, languagePref? }
//
// Security rules (EDD § Auth Module / § Data Encryption):
//   - Changing email or phone triggers OTP verification before the change is
//     persisted. The VERIFY link is shown next to the changed field label.
//   - Ghana Card numbers are AES-256 encrypted at application layer.

class EditProfileState {
  final String fullName;
  final String email;
  final String phoneNumber;
  final String ghanaCard;
  final String originalEmail;
  final String originalPhone;
  final bool isSaving;
  final bool isSaved;
  final String? errorMessage;

  const EditProfileState({
    this.fullName = '',
    this.email = '',
    this.phoneNumber = '',
    this.ghanaCard = '',
    this.originalEmail = '',
    this.originalPhone = '',
    this.isSaving = false,
    this.isSaved = false,
    this.errorMessage,
  });

  bool get emailChanged =>
      email.isNotEmpty && email.trim() != originalEmail.trim();

  bool get phoneChanged =>
      phoneNumber.isNotEmpty && phoneNumber.trim() != originalPhone.trim();

  bool get showVerificationWarning => emailChanged || phoneChanged;

  bool get canSave => !isSaving && !isSaved;

  EditProfileState copyWith({
    String? fullName,
    String? email,
    String? phoneNumber,
    String? ghanaCard,
    String? originalEmail,
    String? originalPhone,
    bool? isSaving,
    bool? isSaved,
    String? errorMessage,
    bool clearError = false,
  }) =>
      EditProfileState(
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        ghanaCard: ghanaCard ?? this.ghanaCard,
        originalEmail: originalEmail ?? this.originalEmail,
        originalPhone: originalPhone ?? this.originalPhone,
        isSaving: isSaving ?? this.isSaving,
        isSaved: isSaved ?? this.isSaved,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
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
        ghanaCard: '',
        originalEmail: profile.email ?? '',
        originalPhone: profile.phone,
      );
    }
  }

  void updateFullName(String v) =>
      state = state.copyWith(fullName: v, clearError: true);
  void updateEmail(String v) =>
      state = state.copyWith(email: v, clearError: true);
  void updatePhoneNumber(String v) =>
      state = state.copyWith(phoneNumber: v, clearError: true);
  void updateGhanaCard(String v) =>
      state = state.copyWith(ghanaCard: v, clearError: true);

  /// PUT /v1/users/me — saves profile changes.
  Future<void> saveChanges() async {
    if (!state.canSave) return;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final error = await _authController.updateProfile(
        UpdateProfileRequest(
          fullName: state.fullName,
          email: state.emailChanged ? state.email : null,
        ),
      );
      if (error != null) {
        state = state.copyWith(isSaving: false, errorMessage: error);
      } else {
        state = state.copyWith(isSaving: false, isSaved: true);
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
