import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../../support/providers/support_providers.dart';

/// Tracks which role the user picked at signup; null until role picker.
final pendingRoleProvider = StateProvider<ProviderType?>((_) => null);

/// When `true`, all registration step widgets should reveal their validation
/// errors — even for fields the user hasn't touched yet. Set to `true` when
/// the user taps "Continue" while the form is invalid. Reset to `false` when
/// navigating to the next step.
final showRegistrationErrorsProvider = StateProvider<bool>((_) => false);

final termsAcceptedProvider = StateProvider<bool>((_) => false);
final privacyAcceptedProvider = StateProvider<bool>((_) => false);

/// Both exact documents must be accepted independently.
final policyAcceptedProvider = Provider<bool>((ref) =>
    ref.watch(termsAcceptedProvider) && ref.watch(privacyAcceptedProvider));

String? validateOptionalReferralCode(String value) {
  final code = value.trim().toUpperCase();
  if (code.isEmpty) return null;
  if (!RegExp(r'^MYSHOP-[A-Z0-9]{6}$').hasMatch(code)) {
    return 'Use MYSHOP- followed by 6 letters or numbers';
  }
  return null;
}

class RegistrationDraftIssue {
  const RegistrationDraftIssue({
    required this.step,
    required this.message,
  });

  final int step;
  final String message;
}

RegistrationDraftIssue? registrationCorrectionForErrorCode(
  String? errorCode,
  ProviderType role,
) {
  if (errorCode == null) return null;
  if (const {
    'EMAIL_ALREADY_EXISTS',
    'INVALID_REFERRAL_CODE',
    'SELF_REFERRAL_NOT_ALLOWED',
    'ROLE_ACCOUNT_REFERRALS_SUSPENDED',
    'REFERRAL_ALREADY_LINKED',
  }.contains(errorCode)) {
    return const RegistrationDraftIssue(step: 0, message: 'Review profile');
  }
  if (role == ProviderType.driver) {
    if (const {
      'VEHICLE_DETAILS_REQUIRED',
      'INVALID_VEHICLE_PLATE',
      'VEHICLE_PLATE_IN_USE',
    }.contains(errorCode)) {
      return const RegistrationDraftIssue(step: 1, message: 'Review vehicle');
    }
    if (const {
      'RIDE_CATEGORIES_REQUIRED',
      'INVALID_RIDE_CATEGORY',
    }.contains(errorCode)) {
      return const RegistrationDraftIssue(
        step: 2,
        message: 'Review ride categories',
      );
    }
    if (errorCode == 'INVALID_REGION') {
      return const RegistrationDraftIssue(step: 3, message: 'Review region');
    }
    if (const {
      'LEGAL_DOCUMENT_CHANGED',
      'LEGAL_DOCUMENTS_UNAVAILABLE',
      'DOCUMENT_NOT_FOUND',
    }.contains(errorCode)) {
      return const RegistrationDraftIssue(step: 4, message: 'Review policies');
    }
    return null;
  }
  if (const {'CATEGORIES_REQUIRED', 'INVALID_CATEGORY'}.contains(errorCode)) {
    return const RegistrationDraftIssue(step: 1, message: 'Review services');
  }
  if (errorCode == 'INVALID_REGION') {
    return const RegistrationDraftIssue(step: 2, message: 'Review region');
  }
  if (const {
    'LEGAL_DOCUMENT_CHANGED',
    'LEGAL_DOCUMENTS_UNAVAILABLE',
    'DOCUMENT_NOT_FOUND',
  }.contains(errorCode)) {
    return const RegistrationDraftIssue(step: 3, message: 'Review policies');
  }
  return null;
}

RegistrationDraftIssue? firstDriverRegistrationIssue(
  DriverRegistrationDraft draft, {
  bool regionSelectionRequired = false,
}) {
  if (Validators.fullName(draft.fullName) != null ||
      Validators.email(draft.email) != null ||
      Validators.ghanaCard(draft.ghanaCardNumber) != null ||
      validateOptionalReferralCode(draft.referralCode) != null) {
    return const RegistrationDraftIssue(
      step: 0,
      message: 'Review the highlighted profile details.',
    );
  }
  if (Validators.required(draft.vehicleMake, 'Make') != null ||
      Validators.required(draft.vehicleModel, 'Model') != null ||
      Validators.vehicleYear(draft.vehicleYear) != null ||
      Validators.licensePlate(draft.vehiclePlate) != null ||
      Validators.required(draft.vehicleColor, 'Colour') != null) {
    return const RegistrationDraftIssue(
      step: 1,
      message: 'Complete the highlighted vehicle details.',
    );
  }
  if (draft.rideCategories.isEmpty) {
    return const RegistrationDraftIssue(
      step: 2,
      message: 'Select at least one available ride category.',
    );
  }
  if (regionSelectionRequired && draft.regionId.isEmpty) {
    return const RegistrationDraftIssue(
      step: 3,
      message: 'Choose an available region.',
    );
  }
  return null;
}

RegistrationDraftIssue? firstArtisanRegistrationIssue(
  ArtisanRegistrationDraft draft, {
  bool regionSelectionRequired = false,
}) {
  if (Validators.fullName(draft.fullName) != null ||
      Validators.email(draft.email) != null ||
      Validators.ghanaCard(draft.ghanaCardNumber) != null ||
      validateOptionalReferralCode(draft.referralCode) != null) {
    return const RegistrationDraftIssue(
      step: 0,
      message: 'Review the highlighted profile details.',
    );
  }
  if (Validators.required(draft.businessName, 'Business name') != null ||
      Validators.required(draft.tradeCategory, 'Primary trade') != null ||
      draft.serviceCategories.isEmpty) {
    return const RegistrationDraftIssue(
      step: 1,
      message: 'Complete your business details and select a service.',
    );
  }
  if (regionSelectionRequired && draft.regionId.isEmpty) {
    return const RegistrationDraftIssue(
      step: 2,
      message: 'Choose an available region.',
    );
  }
  return null;
}

final registrationLegalDocumentsProvider =
    FutureProvider.family<RequiredLegalDocuments, ProviderType>((ref, role) {
  return ref.watch(legalServiceProvider).getRequired(
        role: role == ProviderType.driver ? 'driver' : 'artisan',
      );
});

/// Driver registration draft.
///
/// Holds form data during the registration wizard. The actual API call
/// happens via [AuthController.registerAndSendOtp] when the user submits
/// their phone number on the phone input screen.
class DriverRegistrationDraft {
  DriverRegistrationDraft({
    this.fullName = '',
    this.email = '',
    this.ghanaCardNumber = '',
    this.vehicleMake = '',
    this.vehicleModel = '',
    this.vehicleYear = '',
    this.vehiclePlate = '',
    this.vehicleColor = '',
    this.rideCategories = const [],
    this.regionId = '',
    this.referralCode = '',
  });

  final String fullName;
  final String email;
  final String ghanaCardNumber;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleYear;
  final String vehiclePlate;
  final String vehicleColor;

  /// Ride category slugs the driver wants to serve (e.g. ['regular','comfort']).
  /// Each is admin-verified before the driver is matchable for that tier.
  final List<String> rideCategories;

  /// Home region UUID (from GET /v1/regions) chosen on the region step.
  /// Empty when the regions endpoint is unavailable — register then omits it
  /// and the backend defaults to the active pilot region.
  final String regionId;

  /// Optional referral code entered at signup. Empty when not provided.
  /// Forwarded to POST /auth/register and transactionally linked to this exact
  /// driver role. Invalid and sibling-owned codes are rejected.
  final String referralCode;

  DriverRegistrationDraft copyWith({
    String? fullName,
    String? email,
    String? ghanaCardNumber,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleYear,
    String? vehiclePlate,
    String? vehicleColor,
    List<String>? rideCategories,
    String? regionId,
    String? referralCode,
  }) =>
      DriverRegistrationDraft(
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        ghanaCardNumber: ghanaCardNumber ?? this.ghanaCardNumber,
        vehicleMake: vehicleMake ?? this.vehicleMake,
        vehicleModel: vehicleModel ?? this.vehicleModel,
        vehicleYear: vehicleYear ?? this.vehicleYear,
        vehiclePlate: vehiclePlate ?? this.vehiclePlate,
        vehicleColor: vehicleColor ?? this.vehicleColor,
        rideCategories: rideCategories ?? this.rideCategories,
        regionId: regionId ?? this.regionId,
        referralCode: referralCode ?? this.referralCode,
      );

  /// fullName and at least one ride category are required for POST /auth/register.
  /// Vehicle details are sent with the same register call and persisted on the
  /// Driver row (admin-editable thereafter).
  bool get isComplete => fullName.isNotEmpty && rideCategories.isNotEmpty;
}

class DriverRegistrationController
    extends StateNotifier<DriverRegistrationDraft> {
  DriverRegistrationController() : super(DriverRegistrationDraft());

  void update(DriverRegistrationDraft draft) => state = draft;
}

final driverRegistrationProvider = StateNotifierProvider<
    DriverRegistrationController, DriverRegistrationDraft>((ref) {
  return DriverRegistrationController();
});

/// Artisan registration draft.
///
/// Holds form data during the registration wizard. The actual API call
/// happens via [AuthController.registerAndSendOtp] when the user submits
/// their phone number on the phone input screen.
class ArtisanRegistrationDraft {
  ArtisanRegistrationDraft({
    this.fullName = '',
    this.email = '',
    this.ghanaCardNumber = '',
    this.businessName = '',
    this.tradeCategory = '',
    this.yearsOfExperience = 0,
    this.serviceCategories = const [],
    this.serviceRadiusKm = 5,
    this.regionId = '',
    this.referralCode = '',
  });

  final String fullName;
  final String email;
  final String ghanaCardNumber;
  final String businessName;
  final String tradeCategory;
  final int yearsOfExperience;
  final List<String> serviceCategories;
  final double serviceRadiusKm;

  /// Home region UUID (from GET /v1/regions) chosen on the region step.
  /// Empty when the regions endpoint is unavailable — register then omits it
  /// and the backend defaults to the active pilot region.
  final String regionId;

  /// Optional referral code entered at signup. Empty when not provided.
  /// Forwarded to POST /auth/register and transactionally linked to this exact
  /// artisan role. Invalid and sibling-owned codes are rejected.
  final String referralCode;

  ArtisanRegistrationDraft copyWith({
    String? fullName,
    String? email,
    String? ghanaCardNumber,
    String? businessName,
    String? tradeCategory,
    int? yearsOfExperience,
    List<String>? serviceCategories,
    double? serviceRadiusKm,
    String? regionId,
    String? referralCode,
  }) =>
      ArtisanRegistrationDraft(
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        ghanaCardNumber: ghanaCardNumber ?? this.ghanaCardNumber,
        businessName: businessName ?? this.businessName,
        tradeCategory: tradeCategory ?? this.tradeCategory,
        yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
        serviceCategories: serviceCategories ?? this.serviceCategories,
        serviceRadiusKm: serviceRadiusKm ?? this.serviceRadiusKm,
        regionId: regionId ?? this.regionId,
        referralCode: referralCode ?? this.referralCode,
      );

  /// Only fullName and serviceCategories are required for POST /auth/register.
  /// Business details are submitted later via profile endpoints.
  bool get isComplete => fullName.isNotEmpty && serviceCategories.isNotEmpty;
}

class ArtisanRegistrationController
    extends StateNotifier<ArtisanRegistrationDraft> {
  ArtisanRegistrationController() : super(ArtisanRegistrationDraft());

  void update(ArtisanRegistrationDraft draft) => state = draft;
}

final artisanRegistrationProvider = StateNotifierProvider<
    ArtisanRegistrationController, ArtisanRegistrationDraft>((ref) {
  return ArtisanRegistrationController();
});
