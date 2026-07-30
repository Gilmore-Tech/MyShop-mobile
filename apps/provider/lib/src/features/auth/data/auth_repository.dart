import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';

sealed class ProviderBootstrapResult {
  const ProviderBootstrapResult();
}

final class ProviderBootstrapNoSession extends ProviderBootstrapResult {
  const ProviderBootstrapNoSession();
}

final class ProviderBootstrapReady extends ProviderBootstrapResult {
  const ProviderBootstrapReady(this.user, this.identity);

  final AuthUser user;
  final AuthSessionIdentity identity;
}

/// Credentials remain present, but the provider profile is temporarily
/// unavailable. This must never be treated as a request for another OTP.
final class ProviderBootstrapDeferred extends ProviderBootstrapResult {
  const ProviderBootstrapDeferred([this.cause]);

  final Object? cause;
}

/// Wraps [AuthService] with token persistence via [TokenStorage].
class AuthRepository {
  AuthRepository({
    required AuthService service,
    required TokenStorage tokenStorage,
    required DeviceIdProvider deviceIdProvider,
    Future<String?> Function(AuthTokenSnapshot expectedSession)? refreshSession,
    Future<AuthTokenSnapshot?> Function(AuthExplicitLogoutFence fence)?
        refreshLogoutSession,
  })  : _service = service,
        _tokenStorage = tokenStorage,
        _deviceIdProvider = deviceIdProvider,
        _refreshSession = refreshSession,
        _refreshLogoutSession = refreshLogoutSession;

  final AuthService _service;
  final TokenStorage _tokenStorage;
  final DeviceIdProvider _deviceIdProvider;
  final Future<String?> Function(AuthTokenSnapshot expectedSession)?
      _refreshSession;
  final Future<AuthTokenSnapshot?> Function(AuthExplicitLogoutFence fence)?
      _refreshLogoutSession;

  Future<({String deviceId, String? deviceInfo})> _deviceContext() async {
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
      legalAcceptances: request.legalAcceptances,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
      displayName: request.displayName,
      businessName: request.businessName,
      email: request.email,
      referralCode: request.referralCode,
      categories: request.categories,
      rideCategories: request.rideCategories,
      regionId: request.regionId,
      shopCapacity: request.shopCapacity,
      maxConcurrentJobs: request.maxConcurrentJobs,
      vehicleMake: request.vehicleMake,
      vehicleModel: request.vehicleModel,
      vehicleYear: request.vehicleYear,
      vehiclePlate: request.vehiclePlate,
      vehicleColor: request.vehicleColor,
    );
    await _service.register(enriched);
  }

  /// Login as an existing driver. Sends OTP.
  ///
  /// [forceLogin] is set true on the retry that fires from the
  /// "Sign me in here, sign out the other device" button on the
  /// ALREADY_LOGGED_IN_ELSEWHERE block dialog. The backend skips the
  /// single-device check at this step; the verifyOtp step then
  /// revokes the prior session.
  Future<void> loginDriver(String phone, {bool forceLogin = false}) async {
    final ctx = await _deviceContext();
    await _service.loginDriver(LoginRequest(
      phone: phone,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
      forceLogin: forceLogin,
    ));
  }

  /// Login as an existing artisan. Sends OTP.
  ///
  /// See [loginDriver] for the meaning of [forceLogin].
  Future<void> loginArtisan(String phone, {bool forceLogin = false}) async {
    final ctx = await _deviceContext();
    await _service.loginArtisan(LoginRequest(
      phone: phone,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
      forceLogin: forceLogin,
    ));
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
    return role;
  }

  /// Submit the one-time exact-session capability issued with the blocked
  /// login conflict. Public endpoint, but not an unproved phone-only action.
  Future<void> requestSessionRecovery(
    String phone,
    String role,
    String challenge,
  ) async {
    final ctx = await _deviceContext();
    await _service.requestSessionRecovery(
      challenge: challenge,
      phone: phone,
      deviceId: ctx.deviceId,
      role: role,
    );
  }

  Future<void> requestRoleAccountRecoveryOtp(
    String phone,
    String role,
  ) async {
    final ctx = await _deviceContext();
    await _service.requestRoleAccountRecoveryOtp(
      RequestRoleAccountRecoveryOtpRequest(
        phone: phone,
        role: role,
        deviceId: ctx.deviceId,
      ),
    );
  }

  Future<RoleAccountRecoveryResult> verifyRoleAccountRecoveryOtp({
    required String phone,
    required String role,
    required String code,
    required String requestKey,
  }) async {
    final ctx = await _deviceContext();
    return _service.verifyRoleAccountRecoveryOtp(
      VerifyRoleAccountRecoveryOtpRequest(
        phone: phone,
        role: role,
        deviceId: ctx.deviceId,
        otp: code,
        requestKey: requestKey,
      ),
    );
  }

  /// Verify OTP and persist the authenticated session.
  ///
  /// Provider sessions have no client-side age limit. They remain stored until
  /// explicit logout, app-data removal, or a terminal server auth response.
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
    final acceptedSession = _acceptedSession(
      result.accessToken,
      result.refreshToken,
    );
    await _finalizeAcceptedSessionBestEffort(
      acceptedSession,
      phone: phone,
      role: acceptedSession.identity?.role,
    );
    return result;
  }

  Future<List<String>> getOtpChannels() => _service.getOtpChannels();

  Future<void> resendOtp({
    required String phone,
    required String channel,
  }) =>
      _service.resendOtp(phone: phone, channel: channel);

  /// Request a provider login OTP without specifying a role. The backend
  /// returns a uniform response whether or not the number is registered.
  Future<void> providerLogin(String phone, {bool forceLogin = false}) async {
    final ctx = await _deviceContext();
    await _service.providerLogin(LoginRequest(
      phone: phone,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
      forceLogin: forceLogin,
    ));
  }

  /// Verify a provider login OTP. On a single-role result the tokens are
  /// persisted before returning; on a dual-role result no tokens are written —
  /// the caller must follow up with [providerSelectRole].
  Future<ProviderVerifyResult> providerVerifyOtp({
    required String phone,
    required String code,
    bool forceLogin = false,
  }) async {
    final ctx = await _deviceContext();
    final result = await _service.providerVerifyOtp(ProviderVerifyOtpRequest(
      phone: phone,
      otp: code,
      deviceId: ctx.deviceId,
      deviceInfo: ctx.deviceInfo,
      forceLogin: forceLogin,
    ));
    if (result is ProviderSession) {
      await _persistSession(result, phone);
    }
    return result;
  }

  /// Exchange a role-selection token + chosen role for a session, persisting
  /// the tokens on success.
  Future<ProviderSession> providerSelectRole({
    required String selectionToken,
    required String role,
    required String phone,
    bool forceLogin = false,
  }) async {
    final session = await _service.providerSelectRole(ProviderSelectRoleRequest(
      selectionToken: selectionToken,
      role: role,
      forceLogin: forceLogin,
    ));
    await _persistSession(session, phone);
    return session;
  }

  Future<void> _persistSession(ProviderSession session, String phone) async {
    // Publish the new complete pair before removing the previous cache. A
    // failed secure write leaves the prior complete session/cache untouched.
    await _tokenStorage.writeTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await _finalizeAcceptedSessionBestEffort(
      _acceptedSession(session.accessToken, session.refreshToken),
      phone: phone,
      role: session.role,
    );
  }

  AuthTokenSnapshot _acceptedSession(
    String accessToken,
    String refreshToken,
  ) =>
      AuthTokenSnapshot(
        accessToken: accessToken,
        refreshToken: refreshToken,
        storageFormat: AuthTokenStorageFormat.versioned,
      );

  Future<void> _finalizeAcceptedSessionBestEffort(
    AuthTokenSnapshot acceptedSession, {
    required String phone,
    required String? role,
  }) async {
    try {
      await _tokenStorage.clearCachedProfileIfCurrent(acceptedSession);
    } catch (error) {
      debugPrint('[AuthRepository] previous profile cleanup deferred: $error');
    }
    try {
      await _tokenStorage.writeSessionMetadataIfCurrent(
        expected: acceptedSession,
        phone: phone,
        role: role,
      );
    } catch (error) {
      debugPrint('[AuthRepository] session metadata write deferred: $error');
    }
  }

  /// Fetch the user's full profile from GET /users/me.
  /// Caches the raw response so [bootstrap] can restore the session offline.
  ///
  /// [activeRole] forces which role profile the returned [AuthUser] resolves
  /// its name/email/photo from. Callers in the login flow pass it so
  /// dual-role identity selection stays explicit even if compatibility
  /// metadata from a previous session is still present. The JWT identity is
  /// the authority and must agree with the requested role.
  Future<AuthUser> fetchProfile({AuthRole? activeRole}) async {
    final requestSession = await _tokenStorage.readTokenSnapshot();
    final requestIdentity = requestSession.identity;
    if (requestSession.accessToken == null || requestIdentity == null) {
      throw const StaleAuthSessionException();
    }
    final sessionRole = AuthRole.fromString(requestIdentity.role);
    if (sessionRole == null ||
        sessionRole == AuthRole.client ||
        (activeRole != null && activeRole != sessionRole)) {
      throw const StaleAuthSessionException();
    }
    final result = await _service.getMeWithRaw();
    if (!_profileMatchesSession(result.profile, requestIdentity)) {
      throw const StaleAuthSessionException();
    }
    final stillCurrent = result.raw.isNotEmpty
        ? await _tokenStorage.writeCachedProfileJsonIfCurrent(
            expectedIdentity: requestIdentity,
            json: jsonEncode(result.raw),
          )
        : (await _tokenStorage.readTokenSnapshot()).belongsTo(requestIdentity);
    if (!stillCurrent) {
      debugPrint(
        '[AuthRepository] stale profile response discarded after session '
        'replacement',
      );
      throw const StaleAuthSessionException();
    }
    return AuthUser.fromProfile(result.profile, activeRole: sessionRole);
  }

  /// Try to restore a session from stored tokens.
  ///
  /// Missing-access and recognized legacy migration states are repaired
  /// through the shared bootstrap refresher. Otherwise the cached profile is
  /// returned immediately so the UI can render offline; the auth interceptor
  /// remains the authority for terminal server auth errors.
  Future<ProviderBootstrapResult> bootstrap({AuthRole? activeRole}) async {
    AuthTokenSnapshot session;
    try {
      session = await _tokenStorage.readTokenSnapshot();
    } catch (error) {
      debugPrint('[Bootstrap] token storage temporarily unavailable: $error');
      return ProviderBootstrapDeferred(error);
    }
    if (session.accessToken != null && session.refreshToken == null) {
      debugPrint(
        '[Bootstrap] access-only legacy state requires explicit recovery',
      );
      return const ProviderBootstrapDeferred(
        AccessOnlyAuthSessionException(),
      );
    }
    if (session.accessToken == null ||
        session.isPreSessionIdCredentialState ||
        session.isInterruptedPreSessionIdUpgrade ||
        session.isSessionRoleAccountIdUpgrade) {
      if (session.refreshToken == null) {
        if (!session.hasCredentials) {
          debugPrint('[Bootstrap] no token pair — unauthenticated');
          return const ProviderBootstrapNoSession();
        }
        return const ProviderBootstrapDeferred();
      }
      final refreshSession = _refreshSession;
      final repairIdentity = session.identity;
      final repairGeneration = session.isInterruptedPreSessionIdUpgrade
          ? session.accessLineage?.generation
          : session.isSessionRoleAccountIdUpgrade
              ? session.generation
              : null;
      final carriedRoleAccountId = session.carriedRoleAccountId;
      final repairPrincipal = session.principal;
      if (repairPrincipal == null || refreshSession == null) {
        debugPrint('[Bootstrap] refresh-only session needs manual retry');
        return const ProviderBootstrapDeferred();
      }
      try {
        final repaired = await refreshSession(session);
        session = await _tokenStorage.readTokenSnapshot();
        final repairedOwnerMatches = repairIdentity != null
            ? session.belongsTo(repairIdentity)
            : repairGeneration != null
                ? session.identity?.generation == repairGeneration &&
                    (carriedRoleAccountId == null ||
                        session.identity?.roleAccountId == carriedRoleAccountId)
                : session.identity?.principal == repairPrincipal;
        if (repaired == null ||
            session.accessToken != repaired ||
            !repairedOwnerMatches) {
          return session.hasCredentials
              ? const ProviderBootstrapDeferred()
              : const ProviderBootstrapNoSession();
        }
      } catch (error) {
        return ProviderBootstrapDeferred(error);
      }
    }
    final sessionIdentity = session.identity;
    final sessionRole = AuthRole.fromString(sessionIdentity?.role);
    if (sessionIdentity == null ||
        sessionRole == null ||
        sessionRole == AuthRole.client ||
        (activeRole != null && activeRole != sessionRole)) {
      return const ProviderBootstrapDeferred();
    }
    debugPrint(
      '[Bootstrap] access token present (len=${session.accessToken!.length})',
    );

    String? cachedJson;
    try {
      cachedJson = await _tokenStorage.readCachedProfileJson();
    } catch (error) {
      return ProviderBootstrapDeferred(error);
    }
    if (cachedJson != null) {
      try {
        final map = jsonDecode(cachedJson) as Map<String, dynamic>;
        final profile = UserProfile.fromJson(map);
        if (!_profileMatchesSession(profile, sessionIdentity)) {
          throw const StaleAuthSessionException();
        }
        debugPrint('[Bootstrap] restored from cached profile');
        return ProviderBootstrapReady(
          AuthUser.fromProfile(
            profile,
            activeRole: sessionRole,
          ),
          sessionIdentity,
        );
      } catch (e) {
        debugPrint(
            '[Bootstrap] cached profile corrupt: $e — falling back to network');
      }
    } else {
      debugPrint('[Bootstrap] no cached profile — fetching /users/me');
    }

    try {
      final profile = await fetchProfile(activeRole: activeRole);
      debugPrint('[Bootstrap] fetched profile from network');
      return ProviderBootstrapReady(profile, sessionIdentity);
    } catch (e) {
      debugPrint('[Bootstrap] fetchProfile failed: $e');
      try {
        final remaining = await _tokenStorage.readTokenSnapshot();
        if (!remaining.hasCredentials) {
          return const ProviderBootstrapNoSession();
        }
      } catch (storageError) {
        return ProviderBootstrapDeferred(storageError);
      }
      return ProviderBootstrapDeferred(e);
    }
  }

  bool _profileMatchesSession(
    UserProfile profile,
    AuthSessionIdentity identity,
  ) {
    return switch (identity.role) {
      'driver' => profile.driver?.id == identity.roleAccountId,
      'artisan' => profile.artisan?.id == identity.roleAccountId,
      _ => false,
    };
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
    final requestIdentity = (await _tokenStorage.readTokenSnapshot()).identity;
    final role = AuthRole.fromString(requestIdentity?.role);
    if (requestIdentity == null || role == null || role == AuthRole.client) {
      throw const StaleAuthSessionException();
    }
    final profile = await _service.updateMe(request);
    if (!_profileMatchesSession(profile, requestIdentity) ||
        !(await _tokenStorage.readTokenSnapshot()).belongsTo(requestIdentity)) {
      throw const StaleAuthSessionException();
    }
    return AuthUser.fromProfile(profile, activeRole: role);
  }

  /// Update driver-specific fields via PUT /users/me/driver.
  /// Returns the updated [AuthUser].
  Future<AuthUser> updateDriverProfile(
    UpdateDriverProfileRequest request,
  ) async {
    final requestIdentity = (await _tokenStorage.readTokenSnapshot()).identity;
    if (requestIdentity == null || requestIdentity.role != 'driver') {
      throw const StaleAuthSessionException();
    }
    final profile = await _service.updateDriver(request);
    if (!_profileMatchesSession(profile, requestIdentity) ||
        !(await _tokenStorage.readTokenSnapshot()).belongsTo(requestIdentity)) {
      throw const StaleAuthSessionException();
    }
    return AuthUser.fromProfile(profile, activeRole: AuthRole.driver);
  }

  /// Update artisan-specific fields via PUT /users/me/artisan.
  /// Returns the updated [AuthUser].
  Future<AuthUser> updateArtisanProfile(
    UpdateArtisanProfileRequest request,
  ) async {
    final requestIdentity = (await _tokenStorage.readTokenSnapshot()).identity;
    if (requestIdentity == null || requestIdentity.role != 'artisan') {
      throw const StaleAuthSessionException();
    }
    final profile = await _service.updateArtisan(request);
    if (!_profileMatchesSession(profile, requestIdentity) ||
        !(await _tokenStorage.readTokenSnapshot()).belongsTo(requestIdentity)) {
      throw const StaleAuthSessionException();
    }
    return AuthUser.fromProfile(profile, activeRole: AuthRole.artisan);
  }

  /// Sign out: revoke the session server-side, then wipe local state.
  ///
  /// We MUST await the backend call before clearing local tokens. The
  /// previous fire-and-forget pattern raced the interceptor's onRequest
  /// (which awaits a storage read for the bearer) against the local
  /// `clearTokens()`. When the clear won, onRequest saw a null token and
  /// rejected `/auth/logout` with `NOT_AUTHENTICATED` before it ever hit
  /// the wire — leaving the backend's Redis active-session entry alive
  /// and blocking the user from signing in on another device under the
  /// same role until that server session expires or is otherwise revoked.
  ///
  /// 5s timeout is a UX cap. Even if it fires, the underlying HTTP
  /// request keeps flying and the backend usually still revokes — but
  /// we don't promise that. Local tokens are cleared in every path so
  /// the user is always "signed out" from the device's perspective.
  Future<bool> logout() async {
    final fence = await _tokenStorage.beginExplicitLogout();
    if (fence == null) {
      await _tokenStorage.clearTokens();
      return true;
    }
    var owner =
        await _tokenStorage.readExplicitLogoutOwner(fence) ?? fence.owner;
    var ownerIdentity = owner.identity;
    final accessExpiry = owner.accessExpiresAt;
    final needsLogoutRepair = ownerIdentity == null ||
        owner.accessToken == null ||
        accessExpiry == null ||
        !accessExpiry.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 2)),
        );
    if (needsLogoutRepair &&
        owner.refreshToken != null &&
        _refreshLogoutSession != null &&
        (owner.isPreSessionIdCredentialState ||
            owner.isInterruptedPreSessionIdUpgrade ||
            owner.isSessionRoleAccountIdUpgrade ||
            owner.identity != null)) {
      try {
        final repaired = await _refreshLogoutSession(fence)
            .timeout(const Duration(seconds: 5));
        if (repaired?.identity != null && repaired?.accessToken != null) {
          owner = repaired!;
          ownerIdentity = repaired.identity;
        }
      } catch (error) {
        debugPrint(
            '[AuthRepo] exact legacy logout owner repair failed: $error');
      }
    }
    debugPrint('[AuthRepo] logout — awaiting backend revocation');
    if (ownerIdentity != null) {
      try {
        await _service
            .logout(
              expectedIdentity: ownerIdentity,
              explicitLogoutSession: owner,
            )
            .timeout(const Duration(seconds: 5));
        debugPrint('[AuthRepo] backend logout ok');
      } on TimeoutException {
        debugPrint('[AuthRepo] backend logout timed out — '
            'session may linger until the server expires or revokes it');
      } catch (e) {
        debugPrint('[AuthRepo] backend logout failed: $e — '
            'session may linger until the server expires or revokes it');
      }
    } else if (owner.hasCredentials) {
      debugPrint(
        '[AuthRepo] backend revocation could not be attempted because the '
        'stored legacy credentials have no provable exact SID',
      );
    }
    debugPrint('[AuthRepo] finishing the fenced local logout');
    final cleared = await _tokenStorage.finishExplicitLogout(fence);
    debugPrint('[AuthRepo] logout() done');
    return cleared || !(await _tokenStorage.readTokenSnapshot()).hasCredentials;
  }

  /// Clear all stored tokens and identity context — does NOT call the
  /// backend. Used by force-logout paths where an explicit terminal server
  /// auth code proved that the current session is dead.
  Future<void> clear() => _tokenStorage.clearTokens();

  /// Clear only the JWT pair, preserving phone/role/cached profile so the
  /// user can sign back in quickly. Used by the SESSION_TAKEN_OVER path.
  Future<void> clearTokensOnly() => _tokenStorage.clearAuthTokensOnly();

  /// Read the stored phone (used for OTP resend).
  Future<String?> readPhone() => _tokenStorage.readPhone();
}
