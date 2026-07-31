import '../models/auth_dtos.dart';
import '../models/user_dtos.dart';
import '../http/token_storage.dart';

/// Auth API contract.
///
/// Implementations:
/// - [MockAuthService] for local UI development
/// - [RealAuthService] for the live backend
abstract class AuthService {
  /// Register a new account. Sends OTP to the phone.
  /// POST /auth/register
  Future<void> register(RegisterRequest request);

  /// Login as an existing driver. Sends OTP to the phone.
  /// POST /auth/login/driver
  Future<void> loginDriver(LoginRequest request);

  /// Login as an existing artisan. Sends OTP to the phone.
  /// POST /auth/login/artisan
  Future<void> loginArtisan(LoginRequest request);

  /// Login as an existing client. Sends OTP to the phone.
  /// POST /auth/login/client
  Future<void> loginClient(LoginRequest request);

  /// Check which roles are registered to a phone number.
  /// POST /auth/check-phone
  /// Returns a list of roles (e.g. ["driver"], ["artisan"], ["driver", "artisan"]).
  Future<List<String>> checkPhone(String phone);

  /// Login with phone number, auto-detecting the user's role.
  /// Tries driver first, then artisan. Returns the detected role.
  Future<String> login(LoginRequest request);

  /// Verify OTP and receive JWT tokens.
  /// POST /auth/verify-otp
  Future<TokenResponse> verifyOtp(VerifyOtpRequest request);

  /// List OTP delivery channels currently available on the backend.
  /// GET /auth/otp/channels
  Future<List<String>> getOtpChannels();

  /// Re-deliver the active OTP through [channel] without generating a new code.
  /// POST /auth/otp/resend
  Future<void> resendOtp({
    required String phone,
    required String channel,
  });

  /// Request a provider login OTP WITHOUT specifying a role. Returns a uniform
  /// acknowledgement whether or not the number is registered (no enumeration
  /// oracle). POST /auth/provider/login
  Future<void> providerLogin(LoginRequest request);

  /// Verify a provider login OTP. One provider role → a [ProviderSession];
  /// both roles → a [ProviderRoleChoice] carrying a selection token.
  /// POST /auth/provider/verify-otp
  Future<ProviderVerifyResult> providerVerifyOtp(
    ProviderVerifyOtpRequest request,
  );

  /// Exchange a role-selection token + the chosen role for a session.
  /// POST /auth/provider/select-role
  Future<ProviderSession> providerSelectRole(ProviderSelectRoleRequest request);

  // Token refresh is owned by [TokenRefresher] (single-flight across
  // REST + main WS + chat WS). Do NOT add a refreshToken() method here
  // — any caller-driven refresh racing the shared single-flight will
  // burn the rotating refresh token and force-logout the user.

  /// Revoke the current refresh token server-side. Best-effort: callers
  /// must clear local tokens regardless of whether this succeeds, since
  /// the backend is also fine with eventual revocation on next /refresh.
  /// POST /v1/auth/logout
  Future<void> logout({
    AuthSessionIdentity? expectedIdentity,
    AuthTokenSnapshot? explicitLogoutSession,
  });

  /// Submit the one-time exact-session recovery capability returned by the
  /// blocked-device conflict. The backend records a request only while that
  /// capability is current and bound to this role and device.
  /// Public endpoint — no auth required.
  /// POST /auth/request-session-recovery
  Future<void> requestSessionRecovery({
    required String challenge,
    required String phone,
    required String deviceId,
    required String role,
  });

  /// Request an OTP for recovery of one soft-deleted retained role.
  /// POST /auth/role-account-recovery/request-otp
  Future<void> requestRoleAccountRecoveryOtp(
    RequestRoleAccountRecoveryOtpRequest request,
  );

  /// Verify phone ownership and durably file the exact-role recovery request.
  /// POST /auth/role-account-recovery/verify-otp
  Future<RoleAccountRecoveryResult> verifyRoleAccountRecoveryOtp(
    VerifyRoleAccountRecoveryOtpRequest request,
  );

  /// Get the current user's full profile.
  /// GET /users/me
  Future<UserProfile> getMe();

  /// Same as [getMe] but returns the raw decoded JSON map alongside the
  /// parsed profile. Used by the repository to cache the response so the
  /// session can be restored offline.
  Future<({UserProfile profile, Map<String, dynamic> raw})> getMeWithRaw();

  /// Update user profile fields.
  /// PUT /users/me
  Future<UserProfile> updateMe(UpdateProfileRequest request);

  /// Update driver-specific fields (display name, vehicle, licence, payout).
  /// PUT /users/me/driver
  Future<UserProfile> updateDriver(UpdateDriverProfileRequest request);

  /// Update artisan-specific fields (display name, business name, payout, etc.).
  /// PUT /users/me/artisan
  Future<UserProfile> updateArtisan(UpdateArtisanProfileRequest request);
}

/// Generic auth exception with a user-facing message.
class AuthException implements Exception {
  AuthException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'AuthException($code): $message';
}
