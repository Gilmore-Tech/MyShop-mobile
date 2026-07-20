import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';

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
    required List<LegalAcceptanceSelection> legalAcceptances,
    String? email,
    String? referralCode,
  }) async {
    final deviceId = await _deviceIdProvider.ensureDeviceId();
    final deviceInfo = await _deviceIdProvider.readDeviceInfo();
    await _service.register(RegisterRequest(
      phone: phone,
      fullName: fullName,
      type: 'client',
      legalAcceptances: legalAcceptances,
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

  /// Login as an existing client. Sends OTP.
  ///
  /// [forceLogin] is set true on the retry that fires from the
  /// "Sign me in here, sign out the other device" button on the
  /// ALREADY_LOGGED_IN_ELSEWHERE block dialog. The backend skips the
  /// single-device check at this step; the verifyOtp step then
  /// revokes the prior session.
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

  /// Submit the one-time exact-session capability issued with the blocked
  /// login conflict. Public endpoint, but not an unproved phone-only action.
  Future<void> requestSessionRecovery(String phone, String challenge) async {
    final deviceId = await _deviceIdProvider.ensureDeviceId();
    await _service.requestSessionRecovery(
      challenge: challenge,
      phone: phone,
      deviceId: deviceId,
      role: 'client',
    );
  }

  Future<void> requestRoleAccountRecoveryOtp(String phone) async {
    final deviceId = await _deviceIdProvider.ensureDeviceId();
    await _service.requestRoleAccountRecoveryOtp(
      RequestRoleAccountRecoveryOtpRequest(
        phone: phone,
        role: 'client',
        deviceId: deviceId,
      ),
    );
  }

  Future<RoleAccountRecoveryResult> verifyRoleAccountRecoveryOtp({
    required String phone,
    required String code,
    required String requestKey,
  }) async {
    final deviceId = await _deviceIdProvider.ensureDeviceId();
    return _service.verifyRoleAccountRecoveryOtp(
      VerifyRoleAccountRecoveryOtpRequest(
        phone: phone,
        role: 'client',
        deviceId: deviceId,
        otp: code,
        requestKey: requestKey,
      ),
    );
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

  Future<List<String>> getOtpChannels() => _service.getOtpChannels();

  Future<void> resendOtp({
    required String phone,
    required String channel,
  }) =>
      _service.resendOtp(phone: phone, channel: channel);

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

  /// Sign out: revoke the session server-side, then wipe local state.
  ///
  /// We MUST await the backend call before clearing local tokens. The
  /// previous fire-and-forget pattern raced the interceptor's onRequest
  /// (which awaits a storage read for the bearer) against the local
  /// `clearTokens()`. When the clear won, onRequest saw a null token and
  /// rejected `/auth/logout` with `NOT_AUTHENTICATED` before it ever hit
  /// the wire — leaving the backend's Redis active-session entry alive
  /// and blocking the user from signing in on another device under the
  /// same role until the 7-day refresh-token TTL elapses.
  ///
  /// 5s timeout is a UX cap. Even if it fires, the underlying HTTP
  /// request keeps flying and the backend usually still revokes — but
  /// we don't promise that. Local tokens are cleared in every path so
  /// the user is always "signed out" from the device's perspective.
  Future<void> logout() async {
    debugPrint('[ClientAuthRepo] logout — awaiting backend revocation');
    try {
      await _service.logout().timeout(const Duration(seconds: 5));
      debugPrint('[ClientAuthRepo] backend logout ok');
    } on TimeoutException {
      debugPrint('[ClientAuthRepo] backend logout timed out — '
          'session may linger until refresh-token TTL');
    } catch (_) {
      debugPrint('[ClientAuthRepo] backend logout failed — '
          'session may linger until refresh-token TTL');
    }
    debugPrint('[ClientAuthRepo] clearing local tokens');
    await _tokenStorage.clearTokens();
    debugPrint('[ClientAuthRepo] logout() done');
  }

  /// Clear all stored tokens and identity context — does NOT call the
  /// backend. Used by force-logout paths where we already know the
  /// session is dead server-side (e.g. interceptor 4xx on /auth/refresh).
  Future<void> clear() => _tokenStorage.clearTokens();

  /// Clear only the JWT pair, preserving phone/role/cached profile so the
  /// user can sign back in quickly. Used by the SESSION_TAKEN_OVER path.
  Future<void> clearTokensOnly() => _tokenStorage.clearAuthTokensOnly();
}
