import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';

/// Wraps [AuthService] with token persistence via [TokenStorage].
class AuthRepository {
  AuthRepository({
    required AuthService service,
    required TokenStorage tokenStorage,
    required DeviceIdProvider deviceIdProvider,
  })  : _service = service,
        _tokenStorage = tokenStorage,
        _deviceIdProvider = deviceIdProvider;

  final AuthService _service;
  final TokenStorage _tokenStorage;
  final DeviceIdProvider _deviceIdProvider;

  /// Read the persisted active role and convert to [AuthRole].
  Future<AuthRole?> _activeRole() async {
    final saved = await _tokenStorage.readRole();
    return saved != null ? AuthRole.fromString(saved) : null;
  }

  Future<({String deviceId, Map<String, dynamic>? deviceInfo})>
      _deviceContext() async {
    final id = await _deviceIdProvider.ensureDeviceId();
    final info = await _deviceIdProvider.readDeviceInfo();
    return (deviceId: id, deviceInfo: info);
  }

  /// Register a new account. Sends OTP — no tokens persisted yet.
  /// Caller may build the [RegisterRequest] without [RegisterRequest.deviceId];
  /// this method fills it in along with [RegisterRequest.deviceInfo] from the
  /// platform.
  Future<void> register(RegisterRequest request) async {
    final ctx = await _deviceContext();
    final enriched = RegisterRequest(
      phone: request.phone,
      fullName: request.fullName,
      type: request.type,
      privacyPolicyAccepted: request.privacyPolicyAccepted,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
      displayName: request.displayName,
      businessName: request.businessName,
      email: request.email,
      referralCode: request.referralCode,
      categories: request.categories,
      shopCapacity: request.shopCapacity,
      maxConcurrentJobs: request.maxConcurrentJobs,
    );
    await _service.register(enriched);
    await _tokenStorage.writePhone(request.phone);
  }

  /// Login as an existing driver. Sends OTP.
  Future<void> loginDriver(String phone) async {
    final ctx = await _deviceContext();
    await _service.loginDriver(LoginRequest(
      phone: phone,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
    ));
    await _tokenStorage.writePhone(phone);
  }

  /// Login as an existing artisan. Sends OTP.
  Future<void> loginArtisan(String phone) async {
    final ctx = await _deviceContext();
    await _service.loginArtisan(LoginRequest(
      phone: phone,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
    ));
    await _tokenStorage.writePhone(phone);
  }

  /// Check which roles are registered to a phone number.
  Future<List<String>> checkPhone(String phone) async {
    return _service.checkPhone(phone);
  }

  /// Login with auto role detection. Returns the detected role.
  Future<String> login(String phone) async {
    final ctx = await _deviceContext();
    final role = await _service.login(LoginRequest(
      phone: phone,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
    ));
    await _tokenStorage.writePhone(phone);
    return role;
  }

  /// Notify support that another device holds the active session and the
  /// user can't sign out on it. Public endpoint — no auth required.
  Future<void> requestSessionRecovery(String phone) async {
    final ctx = await _deviceContext();
    await _service.requestSessionRecovery(
      phone: phone,
      deviceId: ctx.deviceId,
    );
  }

  /// Verify OTP → persist tokens and stamp the session start time so the
  /// 7-day [kSessionTtl] window can be enforced on bootstrap.
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
    await _tokenStorage.writeSessionStartedAt(DateTime.now());
    return result;
  }

  /// Fetch the user's full profile from GET /users/me.
  /// Caches the raw response so [bootstrap] can restore the session offline.
  Future<AuthUser> fetchProfile() async {
    final result = await _service.getMeWithRaw();
    if (result.raw.isNotEmpty) {
      await _tokenStorage.writeCachedProfileJson(jsonEncode(result.raw));
    }
    return AuthUser.fromProfile(result.profile,
        activeRole: await _activeRole());
  }

  /// Try to restore a session from stored tokens.
  ///
  /// Strategy:
  ///   1. No access token → not signed in.
  ///   2. Session older than [kSessionTtl] → wipe and force re-login.
  ///   3. Otherwise return the cached profile immediately so the UI can
  ///      render even when the device is offline. The auth interceptor
  ///      still kicks the user out if the backend rejects the token.
  Future<AuthUser?> bootstrap() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null) {
      debugPrint('[Bootstrap] no access token — unauthenticated');
      return null;
    }
    debugPrint('[Bootstrap] access token present (len=${token.length})');

    final startedAt = await _tokenStorage.readSessionStartedAt();
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > kSessionTtl) {
      debugPrint(
          '[Bootstrap] session TTL expired (started $startedAt) — clearing');
      await _tokenStorage.clearTokens();
      return null;
    }
    debugPrint('[Bootstrap] session started $startedAt — within TTL');

    final cachedJson = await _tokenStorage.readCachedProfileJson();
    if (cachedJson != null) {
      try {
        final map = jsonDecode(cachedJson) as Map<String, dynamic>;
        final profile = UserProfile.fromJson(map);
        debugPrint('[Bootstrap] restored from cached profile');
        return AuthUser.fromProfile(profile, activeRole: await _activeRole());
      } catch (e) {
        debugPrint(
            '[Bootstrap] cached profile corrupt: $e — falling back to network');
      }
    } else {
      debugPrint('[Bootstrap] no cached profile — fetching /users/me');
    }

    try {
      final profile = await fetchProfile();
      debugPrint('[Bootstrap] fetched profile from network');
      return profile;
    } catch (e) {
      debugPrint('[Bootstrap] fetchProfile failed: $e');
      return null;
    }
  }

  /// Background refresh of the cached profile. Safe to call after a
  /// successful [bootstrap] — failures are swallowed so a network blip never
  /// signs the user out.
  Future<AuthUser?> refreshProfileQuiet() async {
    try {
      return await fetchProfile();
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

  /// Read the stored phone (used for OTP resend).
  Future<String?> readPhone() => _tokenStorage.readPhone();
}
