import 'package:api_client/api_client.dart' show AuthErrorCodes;
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

/// Legal acceptance is scoped to the exact provider role being registered.
/// A Driver review must never satisfy the separate Artisan registration.
final termsAcceptedProvider =
    StateProvider.family<bool, ProviderType>((_, __) => false);
final privacyAcceptedProvider =
    StateProvider.family<bool, ProviderType>((_, __) => false);

/// Both exact documents must be accepted independently.
final policyAcceptedProvider = Provider.family<bool, ProviderType>((ref, role) {
  return ref.watch(termsAcceptedProvider(role)) &&
      ref.watch(privacyAcceptedProvider(role));
});

String? validateRegistrationEmail(String value) =>
    Validators.email(value.trim());

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
    'INVALID_PLATFORM_REFERRAL_CODE',
    'PLATFORM_REFERRAL_CODE_INACTIVE',
    'PLATFORM_SIGNUP_ATTRIBUTION_SUSPENDED',
    'SIGNUP_ATTRIBUTION_ALREADY_LINKED',
    AuthErrorCodes.invalidPersonName,
    'REGISTRATION_RESTART_REQUIRED',
    AuthErrorCodes.registrationStateChanged,
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

/// Routes structured backend validation fields back to the wizard section
/// that owns them. Unknown fields stay on the phone screen rather than
/// guessing and sending the user to an unrelated step.
RegistrationDraftIssue? registrationCorrectionForFieldErrors(
  Map<String, String> fieldErrors,
  ProviderType role,
) {
  final fields = fieldErrors.keys.map((field) => field.toLowerCase()).toSet();
  if (fields.intersection(const {
    'fullname',
    'displayname',
    'legalname',
    'email',
    'referralcode',
  }).isNotEmpty) {
    return const RegistrationDraftIssue(step: 0, message: 'Review profile');
  }

  if (role == ProviderType.driver) {
    if (fields.intersection(const {
      'vehiclemake',
      'vehiclemodel',
      'vehicleyear',
      'vehicleplate',
      'vehiclecolor',
    }).isNotEmpty) {
      return const RegistrationDraftIssue(step: 1, message: 'Review vehicle');
    }
    if (fields.contains('ridecategories')) {
      return const RegistrationDraftIssue(
        step: 2,
        message: 'Review ride categories',
      );
    }
    if (fields.contains('regionid')) {
      return const RegistrationDraftIssue(step: 3, message: 'Review region');
    }
    if (fields.contains('legalacceptances')) {
      return const RegistrationDraftIssue(step: 4, message: 'Review policies');
    }
    return null;
  }

  if (fields.intersection(const {
    'businessname',
    'categories',
    'shopcapacity',
    'maxconcurrentjobs',
  }).isNotEmpty) {
    return const RegistrationDraftIssue(
      step: 1,
      message: 'Review business details',
    );
  }
  if (fields.contains('regionid')) {
    return const RegistrationDraftIssue(step: 2, message: 'Review region');
  }
  if (fields.contains('legalacceptances')) {
    return const RegistrationDraftIssue(step: 3, message: 'Review policies');
  }
  return null;
}

RegistrationDraftIssue? firstDriverRegistrationIssue(
  DriverRegistrationDraft draft, {
  bool regionSelectionRequired = false,
}) {
  if (Validators.fullName(draft.fullName) != null ||
      validateRegistrationEmail(draft.email) != null ||
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
      validateRegistrationEmail(draft.email) != null ||
      validateOptionalReferralCode(draft.referralCode) != null) {
    return const RegistrationDraftIssue(
      step: 0,
      message: 'Review the highlighted profile details.',
    );
  }
  if (Validators.required(draft.businessName, 'Business name') != null ||
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
    this.businessName = '',
    this.serviceCategories = const [],
    this.serviceRadiusKm = 5,
    this.regionId = '',
    this.referralCode = '',
  });

  final String fullName;
  final String email;
  final String businessName;
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
    String? businessName,
    List<String>? serviceCategories,
    double? serviceRadiusKm,
    String? regionId,
    String? referralCode,
  }) =>
      ArtisanRegistrationDraft(
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        businessName: businessName ?? this.businessName,
        serviceCategories: serviceCategories ?? this.serviceCategories,
        serviceRadiusKm: serviceRadiusKm ?? this.serviceRadiusKm,
        regionId: regionId ?? this.regionId,
        referralCode: referralCode ?? this.referralCode,
      );

  /// Full name, business name, and service categories are sent during
  /// registration. Service radius remains the one post-signup profile update.
  bool get isComplete =>
      fullName.isNotEmpty &&
      businessName.isNotEmpty &&
      serviceCategories.isNotEmpty;
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
