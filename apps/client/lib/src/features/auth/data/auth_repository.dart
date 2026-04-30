import 'package:api_client/api_client.dart';

/// Wraps [AuthService] with token persistence via [TokenStorage].
/// Client-specific: uses loginClient instead of loginDriver/loginArtisan.
class ClientAuthRepository {
  ClientAuthRepository({
    required AuthService service,
    required TokenStorage tokenStorage,
    required DeviceIdProvider deviceIdProvider,
  })  : _service = service,
        _tokenStorage = tokenStorage,
        _deviceIdProvider = deviceIdProvider;

  final AuthService _service;
  final TokenStorage _tokenStorage;
  final DeviceIdProvider _deviceIdProvider;

  /// Register a new client account. Sends OTP — no tokens persisted yet.
  Future<void> register({
    required String phone,
    required String fullName,
    required bool privacyPolicyAccepted,
    String? email,
    String? referralCode,
  }) async {
    final deviceId = await _deviceIdProvider.ensureDeviceId();
    final deviceInfo = await _deviceIdProvider.readDeviceInfo();
    await _service.register(RegisterRequest(
      phone: phone,
      fullName: fullName,
      type: 'client',
      privacyPolicyAccepted: privacyPolicyAccepted,
      deviceId: deviceId,
      deviceInfo: deviceInfo,
      email: email,
      referralCode: referralCode,
    ));
    await _tokenStorage.writePhone(phone);
  }

  /// Check which roles are registered to this phone.
  /// Returns list like ["client"], ["driver", "client"], or [] if unknown.
  Future<List<String>> checkPhone(String phone) async {
    return _service.checkPhone(phone);
  }

  /// Login as an existing client. Sends OTP. [forceLogin] is set to true
  /// after the user confirms the take-over prompt.
  Future<void> loginClient(String phone, {bool forceLogin = false}) async {
    final deviceId = await _deviceIdProvider.ensureDeviceId();
    final deviceInfo = await _deviceIdProvider.readDeviceInfo();
    await _service.loginClient(LoginRequest(
      phone: phone,
      deviceId: deviceId,
      deviceInfo: deviceInfo,
      forceLogin: forceLogin,
    ));
    await _tokenStorage.writePhone(phone);
  }

  /// Verify OTP → persist tokens.
  Future<TokenResponse> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final result = await _service.verifyOtp(
      VerifyOtpRequest(phone: phone, otp: code),
    );
    await _tokenStorage.writeTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    await _tokenStorage.writePhone(phone);
    await _tokenStorage.writeRole('client');
    return result;
  }

  /// Fetch the user's full profile from GET /users/me.
  Future<UserProfile> fetchProfile() async {
    return _service.getMe();
  }

  /// Try to restore a session from stored tokens.
  /// Returns null if no valid session exists.
  Future<UserProfile?> bootstrap() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null) return null;
    try {
      return await _service.getMe();
    } catch (_) {
      return null;
    }
  }

  /// Update the user's profile via PUT /users/me.
  Future<UserProfile> updateProfile(UpdateProfileRequest request) async {
    return _service.updateMe(request);
  }

  /// Read the stored phone (used for OTP resend).
  Future<String?> readPhone() => _tokenStorage.readPhone();

  /// Sign out: revoke the refresh token server-side (best effort) and wipe
  /// local identity context. Used by the explicit logout button.
  Future<void> logout() async {
    try {
      await _service.logout();
    } catch (_) {
      // Best-effort. Even if the backend call fails (network down, token
      // already expired), proceed to wipe local state — the user wants out.
    }
    await _tokenStorage.clearTokens();
  }

  /// Clear all stored tokens and identity context — does NOT call the
  /// backend. Used by force-logout paths where we already know the
  /// session is dead server-side (e.g. interceptor 4xx on /auth/refresh).
  Future<void> clear() => _tokenStorage.clearTokens();

  /// Clear only the JWT pair, preserving phone/role/cached profile so the
  /// user can sign back in quickly. Used by the SESSION_TAKEN_OVER path.
  Future<void> clearTokensOnly() => _tokenStorage.clearAuthTokensOnly();
}
