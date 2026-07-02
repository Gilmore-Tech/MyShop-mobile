/// DTOs for the auth endpoints.
/// Matches the contract in `docs/mobile-api-endpoints.md`.

/// POST /auth/register request body.
///
/// [deviceId] is required by the backend but defaults to an empty string at
/// the construction site — the repository layer is responsible for filling
/// it in from [DeviceIdProvider] before the request hits the network. This
/// keeps controllers free of device-management concerns.
class RegisterRequest {
  const RegisterRequest({
    required this.phone,
    required this.fullName,
    required this.type,
    required this.privacyPolicyAccepted,
    this.deviceId = '',
    this.deviceInfo,
    this.displayName,
    this.businessName,
    this.email,
    this.referralCode,
    this.categories,
    this.rideCategories,
    this.regionId,
    this.shopCapacity,
    this.maxConcurrentJobs,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleYear,
    this.vehiclePlate,
    this.vehicleColor,
  });

  final String phone;
  final String fullName;
  final String type; // "client", "driver", or "artisan"
  final bool privacyPolicyAccepted;
  final String deviceId;
  final Map<String, dynamic>? deviceInfo;
  final String? displayName; // public-facing name for this role
  final String? businessName; // artisan only — trade/shop name
  final String? email;
  final String? referralCode;
  final List<String>? categories; // artisan only — service category UUIDs
  final List<String>?
      rideCategories; // driver only — ride category slugs (admin-verified)
  final String?
      regionId; // provider only — home region UUID from GET /v1/regions
  final String? shopCapacity; // "solo" or "multi"
  final int? maxConcurrentJobs; // 2-3, only when shopCapacity = "multi"
  final String? vehicleMake; // driver only
  final String? vehicleModel; // driver only
  final int? vehicleYear; // driver only
  final String? vehiclePlate; // driver only
  final String? vehicleColor; // driver only

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'phone': phone,
      'fullName': fullName,
      'type': type,
      'privacyPolicyAccepted': privacyPolicyAccepted,
      'deviceId': deviceId,
    };
    if (deviceInfo != null) json['deviceInfo'] = deviceInfo;
    if (displayName != null) json['displayName'] = displayName;
    if (businessName != null) json['businessName'] = businessName;
    if (email != null) json['email'] = email;
    if (referralCode != null) json['referralCode'] = referralCode;
    if (categories != null) json['categories'] = categories;
    if (rideCategories != null) json['rideCategories'] = rideCategories;
    if (regionId != null) json['regionId'] = regionId;
    if (shopCapacity != null) json['shopCapacity'] = shopCapacity;
    if (maxConcurrentJobs != null) {
      json['maxConcurrentJobs'] = maxConcurrentJobs;
    }
    if (vehicleMake != null) json['vehicleMake'] = vehicleMake;
    if (vehicleModel != null) json['vehicleModel'] = vehicleModel;
    if (vehicleYear != null) json['vehicleYear'] = vehicleYear;
    if (vehiclePlate != null) json['vehiclePlate'] = vehiclePlate;
    if (vehicleColor != null) json['vehicleColor'] = vehicleColor;
    return json;
  }
}

/// POST /auth/login/{role} request body.
///
/// [deviceId] is required so the backend can enforce one-active-session-per-
/// account. When another device already holds the session, the backend
/// returns 409 ALREADY_LOGGED_IN_ELSEWHERE. The user can either request
/// session recovery from support or — by tapping "Sign me in here, sign
/// out the other device" on the block dialog — retry with [forceLogin]
/// set to true. With force-login the backend skips the single-device
/// check at this step, sends the OTP, and the verifyOtp step revokes
/// the prior session as part of the takeover.
class LoginRequest {
  const LoginRequest({
    required this.phone,
    required this.deviceId,
    this.deviceInfo,
    this.forceLogin = false,
  });

  final String phone;
  final String deviceId;
  final Map<String, dynamic>? deviceInfo;
  final bool forceLogin;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'phone': phone,
      'deviceId': deviceId,
    };
    if (deviceInfo != null) json['deviceInfo'] = deviceInfo;
    if (forceLogin) json['forceLogin'] = true;
    return json;
  }
}

/// POST /auth/request-session-recovery request body.
///
/// Sent when the user can't reach the device that's currently holding the
/// session (lost phone, etc.). Backend records the request and notifies
/// support so the operator can manually revoke the active session.
class SessionRecoveryRequest {
  const SessionRecoveryRequest({
    required this.phone,
    required this.deviceId,
  });

  final String phone;
  final String deviceId;

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'deviceId': deviceId,
      };
}

/// Body for POST /auth/check-phone. Phone-only — no device context needed.
class PhoneOnlyRequest {
  const PhoneOnlyRequest({required this.phone});

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

/// POST /auth/provider/verify-otp request body. Role-agnostic — the backend
/// resolves the provider role(s) after verifying the code.
class ProviderVerifyOtpRequest {
  const ProviderVerifyOtpRequest({
    required this.phone,
    required this.otp,
    required this.deviceId,
    this.deviceInfo,
    this.forceLogin = false,
  });

  final String phone;
  final String otp;
  final String deviceId;
  final Map<String, dynamic>? deviceInfo;
  final bool forceLogin;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'phone': phone,
      'otp': otp,
      'deviceId': deviceId,
    };
    if (deviceInfo != null) json['deviceInfo'] = deviceInfo;
    if (forceLogin) json['forceLogin'] = true;
    return json;
  }
}

/// POST /auth/provider/select-role request body. Exchanges the selection token
/// (from a dual-role verify) plus the chosen role for a session.
class ProviderSelectRoleRequest {
  const ProviderSelectRoleRequest({
    required this.selectionToken,
    required this.role,
    this.forceLogin = false,
  });

  final String selectionToken;
  final String role; // 'driver' | 'artisan'
  final bool forceLogin;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'selectionToken': selectionToken,
      'role': role,
    };
    if (forceLogin) json['forceLogin'] = true;
    return json;
  }
}

/// Result of POST /auth/provider/verify-otp. Either a ready session (single
/// provider role) or a role choice (the account holds both driver + artisan).
sealed class ProviderVerifyResult {
  const ProviderVerifyResult();

  /// Parse the backend payload, discriminating on the `multiRole` flag.
  factory ProviderVerifyResult.fromJson(Map<String, dynamic> json) {
    if (json['multiRole'] == true) {
      return ProviderRoleChoice(
        roles: (json['roles'] as List).cast<String>(),
        selectionToken: json['selectionToken'] as String,
      );
    }
    return ProviderSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      role: json['role'] as String,
    );
  }
}

/// Single-role verify (or select-role) outcome: tokens + the resolved role.
class ProviderSession extends ProviderVerifyResult {
  const ProviderSession({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
  });

  factory ProviderSession.fromJson(Map<String, dynamic> json) =>
      ProviderSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        role: json['role'] as String,
      );

  final String accessToken;
  final String refreshToken;
  final String role; // 'driver' | 'artisan'
}

/// Dual-role verify outcome: the user must pick a role, then call select-role
/// with [selectionToken].
class ProviderRoleChoice extends ProviderVerifyResult {
  const ProviderRoleChoice({
    required this.roles,
    required this.selectionToken,
  });

  final List<String> roles; // ['driver', 'artisan']
  final String selectionToken;
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
