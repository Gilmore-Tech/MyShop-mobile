import '../models/auth_dtos.dart';
import '../models/user_dtos.dart';

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
  Future<void> loginDriver(String phone);

  /// Login as an existing artisan. Sends OTP to the phone.
  /// POST /auth/login/artisan
  Future<void> loginArtisan(String phone);

  /// Login as an existing client. Sends OTP to the phone.
  /// POST /auth/login/client
  Future<void> loginClient(String phone);

  /// Check which roles are registered to a phone number.
  /// POST /auth/check-phone
  /// Returns a list of roles (e.g. ["driver"], ["artisan"], ["driver", "artisan"]).
  Future<List<String>> checkPhone(String phone);

  /// Login with phone number, auto-detecting the user's role.
  /// Tries driver first, then artisan. Returns the detected role.
  Future<String> login(String phone);

  /// Verify OTP and receive JWT tokens.
  /// POST /auth/verify-otp
  Future<TokenResponse> verifyOtp(VerifyOtpRequest request);

  /// Refresh an expired access token.
  /// POST /auth/refresh
  Future<String> refreshToken(String refreshToken);

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
