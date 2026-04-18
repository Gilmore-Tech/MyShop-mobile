import 'package:api_client/api_client.dart';

/// Wraps [AuthService] with token persistence via [TokenStorage].
/// Client-specific: uses loginClient instead of loginDriver/loginArtisan.
class ClientAuthRepository {
  ClientAuthRepository({
    required AuthService service,
    required TokenStorage tokenStorage,
  })  : _service = service,
        _tokenStorage = tokenStorage;

  final AuthService _service;
  final TokenStorage _tokenStorage;

  /// Register a new client account. Sends OTP — no tokens persisted yet.
  Future<void> register({
    required String phone,
    required String fullName,
    required bool privacyPolicyAccepted,
    String? email,
    String? referralCode,
  }) async {
    await _service.register(RegisterRequest(
      phone: phone,
      fullName: fullName,
      type: 'client',
      privacyPolicyAccepted: privacyPolicyAccepted,
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

  /// Login as an existing client. Sends OTP.
  Future<void> loginClient(String phone) async {
    await _service.loginClient(phone);
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

  /// Clear all stored tokens and phone.
  Future<void> clear() => _tokenStorage.clearTokens();
}
