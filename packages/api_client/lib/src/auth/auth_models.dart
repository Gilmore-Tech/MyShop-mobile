/// Lightweight DTOs for the auth flow. Plain Dart classes — no codegen.
enum AuthRole { driver, artisan }

class AuthUser {
  const AuthUser({
    required this.id,
    required this.phone,
    required this.role,
    required this.fullName,
    required this.isVerified,
  });

  final String id;
  final String phone;
  final AuthRole role;
  final String fullName;
  final bool isVerified;
}

class OtpRequestResult {
  const OtpRequestResult({required this.otpId, required this.expiresAt});
  final String otpId;
  final DateTime expiresAt;
}

class OtpVerifyResult {
  const OtpVerifyResult({
    required this.accessToken,
    required this.refreshToken,
    required this.isNewUser,
    this.user,
  });

  final String accessToken;
  final String refreshToken;
  final bool isNewUser;
  final AuthUser? user;
}

class DriverRegistrationPayload {
  const DriverRegistrationPayload({
    required this.fullName,
    required this.email,
    required this.ghanaCardNumber,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleYear,
    required this.vehiclePlate,
    required this.vehicleColor,
  });

  final String fullName;
  final String email;
  final String ghanaCardNumber;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleYear;
  final String vehiclePlate;
  final String vehicleColor;
}

class ArtisanRegistrationPayload {
  const ArtisanRegistrationPayload({
    required this.fullName,
    required this.email,
    required this.ghanaCardNumber,
    required this.businessName,
    required this.tradeCategory,
    required this.yearsOfExperience,
    required this.serviceCategories,
    required this.serviceRadiusKm,
  });

  final String fullName;
  final String email;
  final String ghanaCardNumber;
  final String businessName;
  final String tradeCategory;
  final int yearsOfExperience;
  final List<String> serviceCategories;
  final double serviceRadiusKm;
}
