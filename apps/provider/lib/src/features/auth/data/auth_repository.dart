import 'package:api_client/api_client.dart';

/// Wraps [AuthService] with token persistence via [TokenStorage].
class AuthRepository {
  AuthRepository({
    required AuthService service,
    required TokenStorage tokenStorage,
  })  : _service = service,
        _tokenStorage = tokenStorage;

  final AuthService _service;
  final TokenStorage _tokenStorage;

  /// Read the persisted active role and convert to [AuthRole].
  Future<AuthRole?> _activeRole() async {
    final saved = await _tokenStorage.readRole();
    return saved != null ? AuthRole.fromString(saved) : null;
  }

  /// Register a new account. Sends OTP — no tokens persisted yet.
  Future<void> register(RegisterRequest request) async {
    await _service.register(request);
    await _tokenStorage.writePhone(request.phone);
  }

  /// Login as an existing driver. Sends OTP.
  Future<void> loginDriver(String phone) async {
    await _service.loginDriver(phone);
    await _tokenStorage.writePhone(phone);
  }

  /// Login as an existing artisan. Sends OTP.
  Future<void> loginArtisan(String phone) async {
    await _service.loginArtisan(phone);
    await _tokenStorage.writePhone(phone);
  }

  /// Check which roles are registered to a phone number.
  Future<List<String>> checkPhone(String phone) async {
    return _service.checkPhone(phone);
  }

  /// Login with auto role detection. Returns the detected role.
  Future<String> login(String phone) async {
    final role = await _service.login(phone);
    await _tokenStorage.writePhone(phone);
    return role;
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
    return result;
  }

  /// Fetch the user's full profile from GET /users/me.
  Future<AuthUser> fetchProfile() async {
    final profile = await _service.getMe();
    return AuthUser.fromProfile(profile, activeRole: await _activeRole());
  }

  /// Try to restore a session from stored tokens.
  /// Returns null if no valid session exists.
  Future<AuthUser?> bootstrap() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null) return null;
    try {
      final profile = await _service.getMe();
      return AuthUser.fromProfile(profile, activeRole: await _activeRole());
    } catch (_) {
      return null;
    }
  }

  /// Update the user's profile via PUT /users/me.
  /// Returns the updated [AuthUser].
  Future<AuthUser> updateProfile(UpdateProfileRequest request) async {
    final profile = await _service.updateMe(request);
    return AuthUser.fromProfile(profile, activeRole: await _activeRole());
  }

  /// Update driver-specific fields via PUT /users/me/driver.
  /// Returns the updated [AuthUser].
  Future<AuthUser> updateDriverProfile(
    UpdateDriverProfileRequest request,
  ) async {
    final profile = await _service.updateDriver(request);
    return AuthUser.fromProfile(profile, activeRole: await _activeRole());
  }

  /// Update artisan-specific fields via PUT /users/me/artisan.
  /// Returns the updated [AuthUser].
  Future<AuthUser> updateArtisanProfile(
    UpdateArtisanProfileRequest request,
  ) async {
    final profile = await _service.updateArtisan(request);
    return AuthUser.fromProfile(profile, activeRole: await _activeRole());
  }

  /// Clear all stored tokens and phone.
  Future<void> clear() => _tokenStorage.clearTokens();

  /// Read the stored phone (used for OTP resend).
  Future<String?> readPhone() => _tokenStorage.readPhone();
}
