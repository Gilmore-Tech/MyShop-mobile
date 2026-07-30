import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';

sealed class ClientBootstrapResult {
  const ClientBootstrapResult();
}

/// No access or refresh credential exists on this install.
final class ClientBootstrapNoSession extends ClientBootstrapResult {
  const ClientBootstrapNoSession();
}

/// A stored session and its role-scoped profile were restored.
final class ClientBootstrapReady extends ClientBootstrapResult {
  const ClientBootstrapReady(this.profile, this.identity);

  final UserProfile profile;
  final AuthSessionIdentity identity;
}

/// Credentials still exist, but the profile could not be loaded yet.
///
/// This is deliberately distinct from [ClientBootstrapNoSession]: a timeout,
/// network interruption, backend 5xx or refresh contention must offer a
/// session retry, not send an existing user through OTP again.
final class ClientBootstrapDeferred extends ClientBootstrapResult {
  const ClientBootstrapDeferred([this.cause]);

  final Object? cause;
}

/// Wraps [AuthService] with token persistence via [TokenStorage].
/// Client-specific: uses loginClient instead of loginDriver/loginArtisan.
class ClientAuthRepository {
  ClientAuthRepository({
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
    // Persist and verify the accepted session before touching the old cache.
    // If replacement fails, the previous complete pair/cache remains intact.
    await _tokenStorage.writeTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    final acceptedSession = AuthTokenSnapshot(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      storageFormat: AuthTokenStorageFormat.versioned,
    );
    try {
      await _tokenStorage.clearCachedProfileIfCurrent(acceptedSession);
    } catch (error) {
      // Cache deletion is defensive and must not discard an accepted session.
      // Exact profile/session guards below keep an old cache from rendering.
      debugPrint('[ClientAuthRepo] previous profile cleanup deferred: $error');
    }
    try {
      await _tokenStorage.writeSessionMetadataIfCurrent(
        expected: acceptedSession,
        phone: phone,
        role: 'client',
      );
    } catch (error) {
      // The JWT remains the source of truth. Metadata can be reconstructed
      // after restart and must never make an accepted login look like OTP
      // verification failed.
      debugPrint('[ClientAuthRepo] session metadata write deferred: $error');
    }
    return result;
  }

  Future<List<String>> getOtpChannels() => _service.getOtpChannels();

  Future<void> resendOtp({
    required String phone,
    required String channel,
  }) =>
      _service.resendOtp(phone: phone, channel: channel);

  /// Fetch the user's full profile from GET /users/me and persist the raw
  /// role-scoped response. A later network/Render interruption must not turn
  /// an otherwise valid stored session into an OTP login.
  Future<UserProfile> fetchProfile() async {
    final requestSession = await _tokenStorage.readTokenSnapshot();
    final requestIdentity = requestSession.identity;
    if (requestSession.accessToken == null || requestIdentity == null) {
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
        '[ClientAuthRepo] stale profile response discarded after session '
        'replacement',
      );
      throw const StaleAuthSessionException();
    }
    return result.profile;
  }

  /// Try to restore a session from stored tokens.
  ///
  /// A stored access token remains the session signal. Return the last
  /// authenticated profile immediately when available; the controller
  /// refreshes it quietly after rendering. This prevents a temporary profile
  /// request failure from redirecting a signed-in client to OTP.
  Future<ClientBootstrapResult> bootstrap() async {
    AuthTokenSnapshot session;
    try {
      session = await _tokenStorage.readTokenSnapshot();
    } catch (error) {
      debugPrint(
        '[ClientAuthRepo] session storage temporarily unavailable: $error',
      );
      return ClientBootstrapDeferred(error);
    }

    if (session.accessToken != null && session.refreshToken == null) {
      return const ClientBootstrapDeferred(
        AccessOnlyAuthSessionException(),
      );
    }

    if (session.accessToken == null ||
        session.isPreSessionIdCredentialState ||
        session.isInterruptedPreSessionIdUpgrade ||
        session.isSessionRoleAccountIdUpgrade) {
      if (session.refreshToken == null) {
        return session.hasCredentials
            ? const ClientBootstrapDeferred()
            : const ClientBootstrapNoSession();
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
        return const ClientBootstrapDeferred();
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
              ? const ClientBootstrapDeferred()
              : const ClientBootstrapNoSession();
        }
      } catch (error) {
        return ClientBootstrapDeferred(error);
      }
    }

    final sessionIdentity = session.identity;
    if (sessionIdentity == null) {
      return const ClientBootstrapDeferred();
    }

    final cachedJson = await _tokenStorage.readCachedProfileJson();
    if (cachedJson != null) {
      try {
        final profile = UserProfile.fromJson(
          jsonDecode(cachedJson) as Map<String, dynamic>,
        );
        if (!_profileMatchesSession(profile, sessionIdentity)) {
          throw const StaleAuthSessionException();
        }
        return ClientBootstrapReady(profile, sessionIdentity);
      } catch (error) {
        debugPrint('[ClientAuthRepo] cached profile unreadable: $error');
      }
    }

    try {
      return ClientBootstrapReady(await fetchProfile(), sessionIdentity);
    } catch (error) {
      debugPrint(
        '[ClientAuthRepo] session profile unavailable; keeping tokens: $error',
      );
      try {
        // The interceptor owns terminal-session decisions. If it cleared both
        // credentials and fired the force-logout callback while /users/me was
        // in flight, reflect that terminal result. Otherwise preserve the
        // session and let the UI retry without OTP.
        final remaining = await _tokenStorage.readTokenSnapshot();
        if (!remaining.hasCredentials) {
          return const ClientBootstrapNoSession();
        }
      } catch (storageError) {
        return ClientBootstrapDeferred(storageError);
      }
      return ClientBootstrapDeferred(error);
    }
  }

  bool _profileMatchesSession(
    UserProfile profile,
    AuthSessionIdentity identity,
  ) =>
      identity.role == 'client' && profile.client?.id == identity.roleAccountId;

  Future<bool> isSessionCurrent(AuthSessionIdentity expected) async =>
      (await _tokenStorage.readTokenSnapshot()).belongsTo(expected);

  Future<AuthSessionIdentity?> readSessionIdentity() async =>
      (await _tokenStorage.readTokenSnapshot()).identity;

  /// Update the user's profile via PUT /users/me.
  Future<UserProfile> updateProfile(UpdateProfileRequest request) async {
    final requestIdentity = (await _tokenStorage.readTokenSnapshot()).identity;
    if (requestIdentity == null || requestIdentity.role != 'client') {
      throw const StaleAuthSessionException();
    }
    final profile = await _service.updateMe(request);
    if (!_profileMatchesSession(profile, requestIdentity) ||
        !(await _tokenStorage.readTokenSnapshot()).belongsTo(requestIdentity)) {
      throw const StaleAuthSessionException();
    }
    return profile;
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
  /// same role until the server expires or otherwise revokes that session.
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
          '[ClientAuthRepo] exact legacy logout owner repair failed: $error',
        );
      }
    }
    debugPrint('[ClientAuthRepo] logout — awaiting backend revocation');
    if (ownerIdentity != null) {
      try {
        await _service
            .logout(
              expectedIdentity: ownerIdentity,
              explicitLogoutSession: owner,
            )
            .timeout(const Duration(seconds: 5));
        debugPrint('[ClientAuthRepo] backend logout ok');
      } on TimeoutException {
        debugPrint('[ClientAuthRepo] backend logout timed out — '
            'session may linger until the server expires or revokes it');
      } catch (_) {
        debugPrint('[ClientAuthRepo] backend logout failed — '
            'session may linger until the server expires or revokes it');
      }
    } else if (owner.hasCredentials) {
      debugPrint(
        '[ClientAuthRepo] backend revocation could not be attempted because '
        'the stored legacy credentials have no provable exact SID',
      );
    }
    debugPrint('[ClientAuthRepo] finishing the fenced local logout');
    final cleared = await _tokenStorage.finishExplicitLogout(fence);
    debugPrint('[ClientAuthRepo] logout() done');
    return cleared || !(await _tokenStorage.readTokenSnapshot()).hasCredentials;
  }

  /// Clear all stored tokens and identity context — does NOT call the
  /// backend. Used by force-logout paths where an explicit terminal server
  /// auth code proved that the current session is dead.
  Future<void> clear() => _tokenStorage.clearTokens();

  /// Clear only the JWT pair, preserving phone/role/cached profile so the
  /// user can sign back in quickly. Used by the SESSION_TAKEN_OVER path.
  Future<void> clearTokensOnly() => _tokenStorage.clearAuthTokensOnly();
}
