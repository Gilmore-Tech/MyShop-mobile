/// DTOs for the auth endpoints.
/// Matches the contract in `docs/mobile-api-endpoints.md`.

/// POST /auth/register request body.
class RegisterRequest {
  const RegisterRequest({
    required this.phone,
    required this.fullName,
    required this.type,
    required this.privacyPolicyAccepted,
    this.displayName,
    this.businessName,
    this.email,
    this.referralCode,
    this.categories,
    this.shopCapacity,
    this.maxConcurrentJobs,
  });

  final String phone;
  final String fullName;
  final String type; // "client", "driver", or "artisan"
  final bool privacyPolicyAccepted;
  final String? displayName; // public-facing name for this role
  final String? businessName; // artisan only — trade/shop name
  final String? email;
  final String? referralCode;
  final List<String>? categories; // artisan only — category UUIDs
  final String? shopCapacity; // "solo" or "multi"
  final int? maxConcurrentJobs; // 2-3, only when shopCapacity = "multi"

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'phone': phone,
      'fullName': fullName,
      'type': type,
      'privacyPolicyAccepted': privacyPolicyAccepted,
    };
    if (displayName != null) json['displayName'] = displayName;
    if (businessName != null) json['businessName'] = businessName;
    if (email != null) json['email'] = email;
    if (referralCode != null) json['referralCode'] = referralCode;
    if (categories != null) json['categories'] = categories;
    if (shopCapacity != null) json['shopCapacity'] = shopCapacity;
    if (maxConcurrentJobs != null) {
      json['maxConcurrentJobs'] = maxConcurrentJobs;
    }
    return json;
  }
}

/// POST /auth/login/{role} request body.
class LoginRequest {
  const LoginRequest({required this.phone});

  final String phone;

  Map<String, dynamic> toJson() => {'phone': phone};
}

/// POST /auth/verify-otp request body.
class VerifyOtpRequest {
  const VerifyOtpRequest({
    required this.phone,
    required this.otp,
  });

  final String phone;
  final String otp;

  Map<String, dynamic> toJson() => {'phone': phone, 'otp': otp};
}

/// Response from POST /auth/verify-otp.
class TokenResponse {
  const TokenResponse({
    required this.accessToken,
    required this.refreshToken,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }

  final String accessToken;
  final String refreshToken;
}

/// POST /auth/refresh request body.
class RefreshRequest {
  const RefreshRequest({required this.refreshToken});

  final String refreshToken;

  Map<String, dynamic> toJson() => {'refreshToken': refreshToken};
}

/// Response from POST /auth/refresh.
class RefreshResponse {
  const RefreshResponse({required this.accessToken});

  factory RefreshResponse.fromJson(Map<String, dynamic> json) {
    return RefreshResponse(accessToken: json['accessToken'] as String);
  }

  final String accessToken;
}
