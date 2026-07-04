import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/providers/provider_type_provider.dart';

/// Tracks which role the user picked at signup; null until role picker.
final pendingRoleProvider = StateProvider<ProviderType?>((_) => null);

/// When `true`, all registration step widgets should reveal their validation
/// errors — even for fields the user hasn't touched yet. Set to `true` when
/// the user taps "Continue" while the form is invalid. Reset to `false` when
/// navigating to the next step.
final showRegistrationErrorsProvider = StateProvider<bool>((_) => false);

/// Whether the user has accepted the privacy policy and terms of service
/// on the review step. Must be `true` before "Create Account" is allowed.
final policyAcceptedProvider = StateProvider<bool>((_) => false);

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
  /// Forwarded to POST /auth/register and linked fire-and-forget by the
  /// backend — a bad code is ignored and never blocks registration.
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
  /// Forwarded to POST /auth/register and linked fire-and-forget by the
  /// backend — a bad code is ignored and never blocks registration.
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
