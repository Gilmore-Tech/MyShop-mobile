import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Edit Profile State ────────────────────────────────────────────────────────
// API: PUT /v1/users/me
//   { fullName?, email?, phoneNumber?, ghanaCard? }
//
// Security rules (EDD § Auth Module / § Data Encryption):
//   - Changing email or phone triggers OTP verification before the change is
//     persisted. The VERIFY link is shown next to the changed field label.
//   - Ghana Card numbers are AES-256 encrypted at application layer — the
//     plaintext value must never be logged or cached in insecure storage.
//   - Phone is the primary identity anchor; duplicate phone across account
//     types is blocked by the backend.

class EditProfileState {
  // ── Current field values ──
  final String fullName;
  final String email;
  final String phoneNumber;
  final String ghanaCard;

  // ── Original values (loaded once at screen open) ──
  final String originalEmail;
  final String originalPhone;

  // ── Async state ──
  final bool isSaving;
  final bool isSaved;
  final String? errorMessage;

  const EditProfileState({
    this.fullName      = '',
    this.email         = '',
    this.phoneNumber   = '',
    this.ghanaCard     = '',
    this.originalEmail = '',
    this.originalPhone = '',
    this.isSaving      = false,
    this.isSaved       = false,
    this.errorMessage,
  });

  /// True when email has been edited away from its original value.
  /// Triggers the "VERIFY" action link and the security warning box.
  bool get emailChanged =>
      email.isNotEmpty && email.trim() != originalEmail.trim();

  /// True when phone has been edited away from its original value.
  /// Also triggers the security warning box.
  bool get phoneChanged =>
      phoneNumber.isNotEmpty && phoneNumber.trim() != originalPhone.trim();

  /// Show the warning box whenever a sensitive field has changed.
  bool get showVerificationWarning => emailChanged || phoneChanged;

  /// "Save Changes" is enabled when not already saving/saved.
  bool get canSave => !isSaving && !isSaved;

  EditProfileState copyWith({
    String? fullName,
    String? email,
    String? phoneNumber,
    String? ghanaCard,
    String? originalEmail,
    String? originalPhone,
    bool?   isSaving,
    bool?   isSaved,
    String? errorMessage,
    bool    clearError = false,
  }) =>
      EditProfileState(
        fullName:      fullName      ?? this.fullName,
        email:         email         ?? this.email,
        phoneNumber:   phoneNumber   ?? this.phoneNumber,
        ghanaCard:     ghanaCard     ?? this.ghanaCard,
        originalEmail: originalEmail ?? this.originalEmail,
        originalPhone: originalPhone ?? this.originalPhone,
        isSaving:      isSaving      ?? this.isSaving,
        isSaved:       isSaved       ?? this.isSaved,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class EditProfileNotifier extends StateNotifier<EditProfileState> {
  EditProfileNotifier() : super(const EditProfileState()) {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // TODO: GET /v1/users/me — populate initial field values
    await Future.delayed(const Duration(milliseconds: 200));
    state = state.copyWith(
      fullName:      'Kofi Mensah',
      email:         'Kofimensah@gmail.com',
      phoneNumber:   '0534599678',
      ghanaCard:     '',
      originalEmail: 'Kofimensah@gmail.com',
      originalPhone: '0534599678',
    );
  }

  void updateFullName(String v)    => state = state.copyWith(fullName: v,    clearError: true);
  void updateEmail(String v)       => state = state.copyWith(email: v,       clearError: true);
  void updatePhoneNumber(String v) => state = state.copyWith(phoneNumber: v, clearError: true);
  void updateGhanaCard(String v)   => state = state.copyWith(ghanaCard: v,   clearError: true);

  /// Triggers OTP flow for changed email/phone before persisting.
  /// PUT /v1/users/me  — backend sends OTP when sensitive fields changed.
  Future<void> saveChanges() async {
    if (!state.canSave) return;
    state = state.copyWith(isSaving: true, clearError: true);
    // TODO: PUT /v1/users/me { fullName, email?, phoneNumber?, ghanaCard? }
    // If emailChanged || phoneChanged → backend initiates OTP; navigate to
    // OTP verification screen with the field being changed as context.
    await Future.delayed(const Duration(milliseconds: 900));
    state = state.copyWith(isSaving: false, isSaved: true);
  }
}

final editProfileProvider =
    StateNotifierProvider.autoDispose<EditProfileNotifier, EditProfileState>(
  (_) => EditProfileNotifier(),
);
