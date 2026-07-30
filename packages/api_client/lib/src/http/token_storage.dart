import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'refresh_attempt_store.dart';

Map<String, dynamic>? _tryDecodeJwtPayload(String? token) {
  if (token == null || token.isEmpty) return null;
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return payload is Map<String, dynamic> ? payload : null;
  } catch (_) {
    return null;
  }
}

/// Stable account and role claims present on both current and pre-SID JWTs.
@immutable
class AuthSessionPrincipal {
  const AuthSessionPrincipal({
    required this.subject,
    required this.role,
  });

  final String subject;
  final String role;

  static AuthSessionPrincipal? tryParseJwt(String? token) {
    final payload = _tryDecodeJwtPayload(token);
    final subject = payload?['sub'];
    final role = payload?['role'];
    if (subject is! String ||
        subject.isEmpty ||
        role is! String ||
        role.isEmpty) {
      return null;
    }
    return AuthSessionPrincipal(subject: subject, role: role);
  }

  @override
  bool operator ==(Object other) =>
      other is AuthSessionPrincipal &&
      subject == other.subject &&
      role == other.role;

  @override
  int get hashCode => Object.hash(subject, role);

  @override
  String toString() => 'AuthSessionPrincipal($subject, $role)';
}

/// Raw identity lineage carried by one JWT.
///
/// `sid` and `roleAccountId` were introduced in separate releases. Parsing
/// them independently is essential: a SID-bearing token without
/// `roleAccountId` is a role-account migration candidate, never a pre-SID
/// token.
@immutable
class AuthTokenLineage {
  const AuthTokenLineage({
    required this.subject,
    required this.role,
    this.roleAccountId,
    this.sessionId,
  });

  final String subject;
  final String role;
  final String? roleAccountId;
  final String? sessionId;

  static AuthTokenLineage? tryParseJwt(String? token) {
    final payload = _tryDecodeJwtPayload(token);
    if (payload == null) return null;
    final subject = payload['sub'];
    final role = payload['role'];
    if (subject is! String ||
        subject.isEmpty ||
        role is! String ||
        role.isEmpty) {
      return null;
    }

    String? optionalClaim(String name) {
      if (!payload.containsKey(name)) return null;
      final value = payload[name];
      if (value is! String || value.isEmpty) {
        throw const FormatException('Malformed JWT identity claim');
      }
      return value;
    }

    try {
      return AuthTokenLineage(
        subject: subject,
        role: role,
        roleAccountId: optionalClaim('roleAccountId'),
        sessionId: optionalClaim('sid'),
      );
    } on FormatException {
      return null;
    }
  }

  AuthSessionPrincipal get principal =>
      AuthSessionPrincipal(subject: subject, role: role);

  AuthSessionGeneration? get generation {
    final sid = sessionId;
    if (sid == null) return null;
    return AuthSessionGeneration(
      subject: subject,
      role: role,
      sessionId: sid,
    );
  }

  AuthSessionIdentity? get identity {
    final sid = sessionId;
    final accountId = roleAccountId;
    if (sid == null || accountId == null) return null;
    return AuthSessionIdentity(
      subject: subject,
      role: role,
      roleAccountId: accountId,
      sessionId: sid,
    );
  }

  bool get isPreSessionId => sessionId == null && roleAccountId == null;
}

/// Server session generation before/independent of role-account migration.
@immutable
class AuthSessionGeneration {
  const AuthSessionGeneration({
    required this.subject,
    required this.role,
    required this.sessionId,
  });

  final String subject;
  final String role;
  final String sessionId;

  AuthSessionPrincipal get principal =>
      AuthSessionPrincipal(subject: subject, role: role);

  @override
  bool operator ==(Object other) =>
      other is AuthSessionGeneration &&
      subject == other.subject &&
      role == other.role &&
      sessionId == other.sessionId;

  @override
  int get hashCode => Object.hash(subject, role, sessionId);

  @override
  String toString() => 'AuthSessionGeneration($subject, $role, $sessionId)';
}

/// Stable server-issued identity for one authenticated role session.
///
/// Refresh rotation keeps this tuple unchanged. A fresh login, role change, or
/// takeover mints a different `sid`, so comparing the complete tuple prevents
/// work started by one account/session from being replayed with another.
@immutable
class AuthSessionIdentity {
  const AuthSessionIdentity({
    required this.subject,
    required this.role,
    required this.roleAccountId,
    required this.sessionId,
  });

  /// Private phone-auth root. This is never a public profile identifier.
  final String subject;
  final String role;

  /// Public role-scoped profile/account ID returned by `/users/me`.
  final String roleAccountId;
  final String sessionId;

  static AuthSessionIdentity? tryParseJwt(String? token) =>
      AuthTokenLineage.tryParseJwt(token)?.identity;

  AuthSessionPrincipal get principal =>
      AuthSessionPrincipal(subject: subject, role: role);

  AuthSessionGeneration get generation => AuthSessionGeneration(
        subject: subject,
        role: role,
        sessionId: sessionId,
      );

  @override
  bool operator ==(Object other) =>
      other is AuthSessionIdentity &&
      subject == other.subject &&
      role == other.role &&
      roleAccountId == other.roleAccountId &&
      sessionId == other.sessionId;

  @override
  int get hashCode => Object.hash(subject, role, roleAccountId, sessionId);

  @override
  String toString() =>
      'AuthSessionIdentity($subject, $role, $roleAccountId, $sessionId)';
}

enum AuthTokenStorageFormat { none, versioned, legacy }

/// One coherent observation of the credentials stored on this install.
@immutable
class AuthTokenSnapshot {
  const AuthTokenSnapshot({
    required this.accessToken,
    required this.refreshToken,
    required this.storageFormat,
  });

  const AuthTokenSnapshot.empty()
      : accessToken = null,
        refreshToken = null,
        storageFormat = AuthTokenStorageFormat.none;

  final String? accessToken;
  final String? refreshToken;
  final AuthTokenStorageFormat storageFormat;

  AuthTokenLineage? get accessLineage =>
      AuthTokenLineage.tryParseJwt(accessToken);

  AuthTokenLineage? get refreshLineage =>
      AuthTokenLineage.tryParseJwt(refreshToken);

  AuthSessionIdentity? get accessIdentity => accessLineage?.identity;

  AuthSessionIdentity? get refreshIdentity => refreshLineage?.identity;

  AuthSessionPrincipal? get accessPrincipal => accessLineage?.principal;

  AuthSessionPrincipal? get refreshPrincipal => refreshLineage?.principal;

  DateTime? get accessExpiresAt {
    final exp = _tryDecodeJwtPayload(accessToken)?['exp'];
    if (exp is! num || !exp.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * Duration.millisecondsPerSecond,
      isUtc: true,
    );
  }

  /// Account and role agreement across the stored pair, including pre-SID
  /// tokens that are eligible only for the explicit bootstrap migration.
  AuthSessionPrincipal? get principal {
    final access = accessPrincipal;
    final refresh = refreshPrincipal;
    if (accessToken != null && refreshToken != null) {
      return access != null && access == refresh ? access : null;
    }
    return access ?? refresh;
  }

  /// Exact session identity, or null for malformed, legacy-without-SID, or a
  /// torn/mixed credential pair. Partial states may still be identified from
  /// their sole token and repaired by the shared refresher.
  AuthSessionIdentity? get identity {
    final access = accessIdentity;
    final refresh = refreshIdentity;
    if (accessToken != null && refreshToken != null) {
      return access != null && access == refresh ? access : null;
    }
    return access ?? refresh;
  }

  /// Coherent private-root/role/SID lineage even while roleAccountId is being
  /// upgraded. A pair with different SIDs or conflicting populated
  /// roleAccountIds has no usable generation.
  AuthSessionGeneration? get generation {
    final access = accessLineage;
    final refresh = refreshLineage;
    final accessGeneration = access?.generation;
    final refreshGeneration = refresh?.generation;
    if (accessToken != null && refreshToken != null) {
      if (accessGeneration == null ||
          refreshGeneration == null ||
          accessGeneration != refreshGeneration ||
          _hasRoleAccountIdConflict) {
        return null;
      }
      return accessGeneration;
    }
    return accessGeneration ?? refreshGeneration;
  }

  String? get carriedRoleAccountId {
    if (_hasRoleAccountIdConflict) return null;
    return accessLineage?.roleAccountId ?? refreshLineage?.roleAccountId;
  }

  bool get _hasRoleAccountIdConflict {
    final access = accessLineage?.roleAccountId;
    final refresh = refreshLineage?.roleAccountId;
    return access != null && refresh != null && access != refresh;
  }

  bool get hasCredentials => accessToken != null || refreshToken != null;
  bool get canRefresh => refreshToken != null && identity != null;

  /// A coherent token state minted before the backend introduced `sid`.
  ///
  /// This state is eligible only for the explicit bootstrap upgrade. A mixed
  /// pair where either token already has a different SID is not legacy.
  bool get isPreSessionIdCredentialState {
    final refresh = refreshLineage;
    final access = accessLineage;
    return identity == null &&
        principal != null &&
        refreshToken != null &&
        refresh?.isPreSessionId == true &&
        (accessToken == null || access?.isPreSessionId == true);
  }

  /// The released two-key writer could be interrupted after persisting the
  /// first SID-bearing access token but before replacing its pre-SID refresh
  /// token. This split state is identifiable without treating arbitrary mixed
  /// credentials as legacy: both tokens must name the same subject and role,
  /// only the access token may carry a SID, and both raw tokens must exist.
  ///
  /// It is not eligible for the ordinary pre-SID migration. Recovery requires
  /// the bootstrap endpoint to verify the signed access token as proof of the
  /// exact active SID before accepting the old refresh credential.
  bool get isInterruptedPreSessionIdUpgrade =>
      identity == null &&
      accessToken != null &&
      refreshToken != null &&
      accessLineage?.generation != null &&
      refreshLineage?.sessionId == null &&
      refreshPrincipal == accessPrincipal &&
      !_hasRoleAccountIdConflict;

  /// A coherent SID generation whose access/refresh pair still lacks
  /// roleAccountId on one or both sides. Bootstrap may rotate this exact raw
  /// state without an access proof because the signed refresh token already
  /// carries the durable SID.
  bool get isSessionRoleAccountIdUpgrade =>
      identity == null &&
      refreshToken != null &&
      generation != null &&
      (accessToken == null ||
          accessLineage?.roleAccountId == null ||
          refreshLineage?.roleAccountId == null);

  bool belongsTo(AuthSessionIdentity expected) => identity == expected;

  bool hasExactRawCredentials(AuthTokenSnapshot expected) =>
      expected.hasCredentials &&
      accessToken == expected.accessToken &&
      refreshToken == expected.refreshToken;

  /// Compare the raw credential epoch as well as its verified server identity.
  ///
  /// Raw equality is required for compare-and-set token mutation: two rotating
  /// refresh tokens can share one SID, but a stale response may only replace
  /// the exact refresh credential it consumed.
  bool isExactCredentialState(AuthTokenSnapshot expected) =>
      identity != null &&
      identity == expected.identity &&
      accessToken == expected.accessToken &&
      refreshToken == expected.refreshToken;
}

/// Durable capability created at the instant a user explicitly signs out.
///
/// The fence is written before any repair or network request. While it
/// remains current, ordinary token readers see no authenticated session and
/// compare-and-set refresh commits cannot publish a successor. The captured
/// owner is retained only in memory so the logout path can still make an
/// exact, best-effort server revocation request.
@immutable
class AuthExplicitLogoutFence {
  const AuthExplicitLogoutFence({
    required this.id,
    required this.owner,
  });

  final String id;
  final AuthTokenSnapshot owner;
}

/// A response completed after its originating session was replaced.
class StaleAuthSessionException implements Exception {
  const StaleAuthSessionException();

  @override
  String toString() => 'StaleAuthSessionException';
}

/// A released two-key writer stopped after persisting access but before
/// refresh. The access token cannot safely mint a refresh credential, so
/// bootstrap preserves the raw state and surfaces explicit recovery instead
/// of pretending the session will survive access expiry.
class AccessOnlyAuthSessionException implements Exception {
  const AccessOnlyAuthSessionException();

  @override
  String toString() => 'AccessOnlyAuthSessionException';
}

/// Exact credential lineage whose terminal server response cleared storage.
///
/// The UI consumes this synchronously after the conditional clear. Carrying
/// the owner prevents a delayed terminal response for session A from
/// unauthenticating a newly-published session B.
@immutable
class AuthForceLogoutEvent {
  const AuthForceLogoutEvent({
    required this.principal,
    this.generation,
    this.roleAccountId,
  });

  factory AuthForceLogoutEvent.fromSnapshot(AuthTokenSnapshot snapshot) {
    final principal = snapshot.principal;
    if (principal == null) {
      throw ArgumentError.value(
        snapshot,
        'snapshot',
        'A force-logout owner must have an identifiable principal',
      );
    }
    return AuthForceLogoutEvent(
      principal: principal,
      generation: snapshot.generation,
      roleAccountId: snapshot.carriedRoleAccountId,
    );
  }

  final AuthSessionPrincipal principal;
  final AuthSessionGeneration? generation;
  final String? roleAccountId;

  /// Whether this terminal event can own a currently-published full session.
  ///
  /// Pre-SID owners intentionally cannot match a published SID session.
  bool owns(AuthSessionIdentity identity) {
    final ownerGeneration = generation;
    if (ownerGeneration == null ||
        ownerGeneration != identity.generation ||
        principal != identity.principal) {
      return false;
    }
    final accountId = roleAccountId;
    return accountId == null || accountId == identity.roleAccountId;
  }
}

/// Non-Keychain install marker used to detect iOS uninstall/reinstall.
///
/// iOS Keychain values can survive uninstall while app preferences do not.
/// Keeping the matching epoch in both stores lets [SecureTokenStorage] reject
/// credentials that belong to a previous installation.
abstract interface class InstallEpochStore {
  Future<String?> readInstallEpoch();
  Future<void> writeInstallEpoch(String epoch);
}

class SharedPreferencesInstallEpochStore implements InstallEpochStore {
  static const preferenceKey = 'auth_install_epoch_v1';

  @override
  Future<String?> readInstallEpoch() async =>
      (await SharedPreferences.getInstance()).getString(preferenceKey);

  @override
  Future<void> writeInstallEpoch(String epoch) async {
    final written = await (await SharedPreferences.getInstance())
        .setString(preferenceKey, epoch);
    if (!written) {
      throw StateError('Install epoch preference could not be persisted');
    }
  }
}

/// Refresh-attempt persistence whose record creation is guarded by the exact
/// logical token pair in the same storage critical section.
abstract interface class SessionBoundRefreshAttemptStore
    implements RefreshAttemptStore {
  Future<String?> readOrCreateIfCurrent(AuthTokenSnapshot expected);
}

/// Abstract interface for token persistence.
/// Keeps the HTTP layer testable without Flutter dependencies.
abstract class TokenStorage {
  Future<AuthTokenSnapshot> readTokenSnapshot();
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> writeAccessToken(String accessToken);

  /// Durably hide the current credential owner before explicit logout does
  /// any repair or network I/O. Returns null when no credentials exist.
  Future<AuthExplicitLogoutFence?> beginExplicitLogout();

  /// Privileged read used only by explicit logout repair. Ordinary readers
  /// continue to observe an empty session while this capability is current.
  Future<AuthTokenSnapshot?> readExplicitLogoutOwner(
    AuthExplicitLogoutFence fence,
  );

  /// Persist a repaired successor while keeping it behind [fence].
  ///
  /// This is the only refresh commit allowed after explicit logout begins.
  /// It exists solely to obtain an exact SID-bearing bearer for server
  /// revocation; it never republishes an authenticated local session.
  Future<bool> replaceExplicitLogoutTokensIfCurrent({
    required AuthExplicitLogoutFence fence,
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  });

  /// Finish local explicit logout. The fenced owner is removed even when the
  /// server request failed; a newer accepted login is never cleared.
  Future<bool> finishExplicitLogout(AuthExplicitLogoutFence fence);

  /// Atomically replace the exact credential state observed by a refresh.
  ///
  /// Returns false when another login/logout/refresh changed storage first.
  Future<bool> replaceTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  });

  /// Upgrade an exact pre-SID credential state to a full session identity.
  ///
  /// This is reserved for bootstrap recovery. The returned pair must agree on
  /// one non-empty SID and retain the legacy token's exact subject and role.
  Future<bool> replaceLegacyTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  });

  /// Finish a released two-key writer's interrupted pre-SID → SID upgrade.
  ///
  /// The old refresh credential is accepted only after the backend verifies
  /// [expected]'s signed SID-bearing access token. Storage then requires the
  /// returned pair to retain that exact identity and compare-and-swaps the
  /// exact split raw state.
  Future<bool> replaceInterruptedLegacyTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  });

  /// Upgrade a coherent SID-bearing generation that lacks roleAccountId on
  /// one or both tokens. The returned pair must preserve exact sub/role/SID,
  /// agree on one roleAccountId, retain any populated old roleAccountId, and
  /// replace only the exact raw state observed by bootstrap.
  Future<bool> replaceSessionLineageTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  });

  /// Wipe everything tied to the user's identity — tokens, phone, role, and
  /// cached profile. Used when the backend tells us the
  /// session is fundamentally dead (TOKEN_EXPIRED / INVALID_TOKEN /
  /// REFRESH_TOKEN_REUSED) or the user explicitly logs out.
  ///
  /// The persistent device ID is preserved across this call — it represents
  /// the install, not the user.
  Future<void> clearTokens();
  Future<bool> clearTokensIfCurrent(AuthTokenSnapshot expected);

  /// Clear the currently stored incarnation of one exact server session.
  ///
  /// Unlike raw compare-and-set clearing, this deliberately accepts access
  /// and refresh rotation within the same SID. It is used by user-initiated
  /// logout, whose server request and local teardown remain bound to the
  /// session that owned the tap even if that session refreshes meanwhile.
  Future<bool> clearTokensForIdentityIfCurrent(
    AuthSessionIdentity expectedIdentity,
  );

  /// Wipe ONLY the JWT pair, preserving phone, role, and cached profile.
  /// Used for SESSION_TAKEN_OVER: the current tokens are
  /// invalidated server-side but the user's identity context is still
  /// useful for a quick re-login on the same device.
  Future<void> clearAuthTokensOnly();
  Future<bool> clearAuthTokensOnlyIfCurrent(AuthTokenSnapshot expected);
  Future<bool> clearAuthTokensOnlyForIdentityIfCurrent(
    AuthSessionIdentity expectedIdentity,
  );

  Future<String?> readPhone();
  Future<void> writePhone(String phone);

  /// Persist account metadata only while the exact newly-issued credential
  /// pair is still current. This prevents a late login completion from
  /// overwriting the role/phone belonging to a replacement account.
  Future<bool> writeSessionMetadataIfCurrent({
    required AuthTokenSnapshot expected,
    String? phone,
    String? role,
  });

  /// Persistent device ID — generated on first install, stable across logins
  /// and logouts, used to disambiguate concurrent sessions for the same user.
  Future<String?> readDeviceId();
  Future<void> writeDeviceId(String deviceId);

  /// The role the user chose at login (e.g. "driver" or "artisan").
  /// Persisted so bootstrap can restore the correct view after restart.
  Future<String?> readRole();
  Future<void> writeRole(String role);

  /// Whether the user has completed the onboarding/welcome screen at least
  /// once. Survives logout — only a full app data clear resets this.
  Future<bool> hasSeenOnboarding();
  Future<void> markOnboardingSeen();

  /// Cached `/users/me` response JSON. Lets bootstrap restore the
  /// authenticated UI when the device is offline at app start.
  Future<String?> readCachedProfileJson();
  Future<void> writeCachedProfileJson(String json);
  Future<bool> writeCachedProfileJsonIfCurrent({
    required AuthSessionIdentity expectedIdentity,
    required String json,
  });

  /// Remove only the cached role profile while preserving the authenticated
  /// token pair and the rest of the install/session metadata.
  ///
  /// A freshly-issued session may belong to a different phone or role than
  /// the previous one on this install. Its first profile fetch must never be
  /// allowed to render the previous account's durable cache.
  Future<void> clearCachedProfile();
  Future<bool> clearCachedProfileIfCurrent(AuthTokenSnapshot expected);
}

class _ExplicitLogoutFenceRecord {
  const _ExplicitLogoutFenceRecord({
    required this.id,
    required this.subject,
    required this.role,
    required this.accessDigest,
    required this.refreshDigest,
    this.sessionId,
    this.roleAccountId,
  });

  final String id;
  final String? subject;
  final String? role;
  final String? sessionId;
  final String? roleAccountId;
  final String? accessDigest;
  final String? refreshDigest;

  bool exactlyMatches(AuthTokenSnapshot snapshot) =>
      _digest(snapshot.accessToken) == accessDigest &&
      _digest(snapshot.refreshToken) == refreshDigest;

  /// Covers every rotation/upgrade successor that can belong to the logout
  /// owner. A pre-SID fence covers only its captured raw predecessor until a
  /// privileged repair returns a concrete SID and evolves the fence. This is
  /// essential: a separately OTP-accepted login for the same principal must
  /// never be hidden or cleared by an older logout.
  bool covers(AuthTokenSnapshot snapshot) {
    if (!snapshot.hasCredentials) return false;
    if (exactlyMatches(snapshot)) return true;
    final expectedSubject = subject;
    final expectedRole = role;
    if (expectedSubject == null || expectedRole == null) {
      return false;
    }
    final principal = snapshot.principal;
    if (principal?.subject != expectedSubject ||
        principal?.role != expectedRole) {
      return false;
    }
    final expectedSessionId = sessionId;
    if (expectedSessionId == null) return false;
    final generation = snapshot.generation;
    if (generation?.sessionId != expectedSessionId) return false;
    final expectedRoleAccountId = roleAccountId;
    final carriedRoleAccountId = snapshot.carriedRoleAccountId;
    return expectedRoleAccountId == null ||
        carriedRoleAccountId == null ||
        carriedRoleAccountId == expectedRoleAccountId;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'subject': subject,
        'role': role,
        'sessionId': sessionId,
        'roleAccountId': roleAccountId,
        'accessDigest': accessDigest,
        'refreshDigest': refreshDigest,
      };

  static _ExplicitLogoutFenceRecord? tryParse(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic> || value['version'] != 1) {
        return null;
      }
      String? optionalString(String key) {
        final field = value[key];
        return field is String && field.isNotEmpty ? field : null;
      }

      final id = optionalString('id');
      if (id == null) return null;
      return _ExplicitLogoutFenceRecord(
        id: id,
        subject: optionalString('subject'),
        role: optionalString('role'),
        sessionId: optionalString('sessionId'),
        roleAccountId: optionalString('roleAccountId'),
        accessDigest: optionalString('accessDigest'),
        refreshDigest: optionalString('refreshDigest'),
      );
    } on Object {
      return null;
    }
  }

  static String? _digest(String? token) =>
      token == null ? null : refreshTokenDigest(token);
}

/// Production implementation backed by Flutter Secure Storage
/// (Keychain on iOS, EncryptedSharedPreferences on Android).
class SecureTokenStorage
    implements TokenStorage, SessionBoundRefreshAttemptStore {
  SecureTokenStorage([
    FlutterSecureStorage? storage,
    bool? recoverOnFailure,
    InstallEpochStore? installEpochStore,
    bool? enforceInstallBoundary,
  ])  : _storage = storage ??
            const FlutterSecureStorage(
              // The plugin's native resetOnError handler deletes the entire
              // encrypted store for *any* exception. A transient keystore or
              // platform-channel failure must not silently turn a valid
              // session into an OTP login, so recovery is classified in Dart
              // instead.
              aOptions: AndroidOptions(resetOnError: false),
            ),
        _recoverOnFailure =
            recoverOnFailure ?? defaultTargetPlatform == TargetPlatform.android,
        _installEpochStore =
            installEpochStore ?? SharedPreferencesInstallEpochStore(),
        _enforceInstallBoundary = enforceInstallBoundary ??
            defaultTargetPlatform == TargetPlatform.iOS;

  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';
  static const _kTokenPair = 'auth_token_pair_v1';
  static const _kPhone = 'auth_phone';
  static const _kOnboardingSeen = 'onboarding_seen';
  static const _kRole = 'auth_role';
  // Removed policy metadata from older builds. Kept only so logout cleans up
  // the obsolete key; authentication is no longer expired by local age.
  static const _kLegacySessionStartedAt = 'auth_session_started_at';
  static const _kCachedProfile = 'auth_cached_profile';
  static const _kDeviceId = 'auth_device_id';
  static const _kInstallBoundary = 'auth_install_boundary_v1';
  static const _kRefreshAttempt = 'auth_refresh_attempt_v1';
  static const _kExplicitLogoutFence = 'auth_explicit_logout_fence_v1';

  final FlutterSecureStorage _storage;
  final bool _recoverOnFailure;
  final InstallEpochStore _installEpochStore;
  final bool _enforceInstallBoundary;
  bool _credentialResetAttemptedForCurrentFailure = false;
  static Future<void> _processOperationTail = Future<void>.value();
  static const _uuid = Uuid();

  /// Serializes all credential and profile-cache mutations in this process.
  ///
  /// FlutterSecureStorage does not expose compare-and-set. Keeping the
  /// read/check/write sequence behind one gate prevents a late refresh or
  /// profile response from slipping between a new login's token write and its
  /// cache cleanup.
  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _processOperationTail;
    final release = Completer<void>();
    _processOperationTail = release.future;
    await previous;
    try {
      if (_enforceInstallBoundary) {
        await _ensureInstallBoundaryUnlocked();
      }
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<void> _ensureInstallBoundaryUnlocked() async {
    final preferenceEpoch = await _installEpochStore.readInstallEpoch();
    final encoded = await _storage.read(key: _kInstallBoundary);
    if (encoded == null) {
      // One-time migration for installs that predate the boundary. Deriving
      // the epoch from the surviving device ID makes interrupted first-run
      // migration deterministic instead of repeatedly minting new epochs.
      final deviceId = await _storage.read(key: _kDeviceId);
      final epoch = deviceId != null && deviceId.isNotEmpty
          ? _uuid.v5(
              Namespace.url.value,
              'com.gilmore.myshop.install:$deviceId',
            )
          : _uuid.v4();
      await _writeInstallBoundaryRecordUnlocked('pending', epoch);
      await _installEpochStore.writeInstallEpoch(epoch);
      await _writeInstallBoundaryRecordUnlocked('active', epoch);
      return;
    }

    final record = _decodeInstallBoundaryRecord(encoded);
    if (record == null) {
      await _resetInstallBoundaryUnlocked(_uuid.v4());
      return;
    }

    switch (record.state) {
      case 'active':
        if (preferenceEpoch == record.epoch) return;
        await _resetInstallBoundaryUnlocked(_uuid.v4());
        return;
      case 'resetting':
        await _resetInstallBoundaryUnlocked(record.epoch);
        return;
      case 'pending':
        if (preferenceEpoch == null) {
          // Resume an interrupted first migration. This is intentionally the
          // only grandfather path; see release docs for the uninstall-before-
          // first-migration limitation.
          await _installEpochStore.writeInstallEpoch(record.epoch);
          await _writeInstallBoundaryRecordUnlocked(
            'active',
            record.epoch,
          );
        } else if (preferenceEpoch == record.epoch) {
          await _writeInstallBoundaryRecordUnlocked(
            'active',
            record.epoch,
          );
        } else {
          await _resetInstallBoundaryUnlocked(_uuid.v4());
        }
        return;
    }
  }

  ({String state, String epoch})? _decodeInstallBoundaryRecord(
    String encoded,
  ) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) return null;
      final state = decoded['state'];
      final epoch = decoded['epoch'];
      if (state is! String ||
          !const {'pending', 'active', 'resetting'}.contains(state) ||
          epoch is! String ||
          epoch.isEmpty) {
        return null;
      }
      return (state: state, epoch: epoch);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeInstallBoundaryRecordUnlocked(
    String state,
    String epoch,
  ) async {
    final encoded = jsonEncode({
      'v': 1,
      'state': state,
      'epoch': epoch,
    });
    await _storage.write(key: _kInstallBoundary, value: encoded);
    if (await _storage.read(key: _kInstallBoundary) != encoded) {
      throw StateError('Install boundary write could not be verified');
    }
  }

  Future<void> _resetInstallBoundaryUnlocked(String epoch) async {
    await _writeInstallBoundaryRecordUnlocked('resetting', epoch);
    for (final key in const [
      _kAccessToken,
      _kRefreshToken,
      _kTokenPair,
      _kPhone,
      _kRole,
      _kLegacySessionStartedAt,
      _kCachedProfile,
      _kDeviceId,
      _kOnboardingSeen,
      _kRefreshAttempt,
      _kExplicitLogoutFence,
    ]) {
      await _storage.delete(key: key);
      if (await _storage.read(key: key) != null) {
        throw StateError('Install boundary cleanup could not delete $key');
      }
    }
    await _installEpochStore.writeInstallEpoch(epoch);
    await _writeInstallBoundaryRecordUnlocked('active', epoch);
  }

  bool _isPermanentCryptoFailure(Object error) {
    if (error is! PlatformException) return false;

    final diagnostic = <Object?>[
      error.code,
      error.message,
      error.details,
    ].whereType<Object>().join(' ');
    const permanentFailureMarkers = <String>{
      'AEADBadTagException',
      'BadPaddingException',
      'IllegalBlockSizeException',
      'InvalidKeyException',
      'KeyPermanentlyInvalidatedException',
    };
    return permanentFailureMarkers.any(diagnostic.contains);
  }

  // Background reads and metadata/device operations are non-destructive.
  // Android master-key recovery is reserved for accepted-login credential
  // preflight, before a newly issued token pair is published.
  Future<String?> _read(String key) => _storage.read(key: key);

  Future<void> _write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> _delete(String key) => _storage.delete(key: key);

  String _encodeTokenPair(String accessToken, String refreshToken) =>
      jsonEncode({
        'version': 1,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      });

  ({String accessToken, String refreshToken}) _decodeTokenPair(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw StateError('Stored token pair has an unsupported format');
    }
    final accessToken = decoded['accessToken'];
    final refreshToken = decoded['refreshToken'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw StateError('Stored token pair is incomplete');
    }
    return (accessToken: accessToken, refreshToken: refreshToken);
  }

  Future<void> _writeTokenPairUnlocked({
    required String accessToken,
    required String refreshToken,
    required AuthTokenSnapshot previous,
  }) async {
    final encoded = _encodeTokenPair(accessToken, refreshToken);
    final next = AuthTokenSnapshot(
      accessToken: accessToken,
      refreshToken: refreshToken,
      storageFormat: AuthTokenStorageFormat.versioned,
    );
    final nextIdentity = next.identity;
    if (nextIdentity == null) {
      throw StateError('Token-pair write requires one exact session identity');
    }
    final mirroredAccess = await _storage.read(key: _kAccessToken);
    final mirroredAccessIdentity =
        AuthSessionIdentity.tryParseJwt(mirroredAccess);
    final sameExactOwner = previous.identity == nextIdentity &&
        (mirroredAccess == null || mirroredAccessIdentity == nextIdentity);

    if (sameExactOwner) {
      // Refresh A is already durable before the request. Publish the successor
      // refresh to the +25 rollback reader first. If canonical commit fails,
      // the current app still has predecessor J1 + attempt A and can replay;
      // a downgraded app has old-access/J2-refresh for the same exact SID.
      await _writeAndVerifyRollbackToken(
        key: _kRefreshToken,
        token: refreshToken,
        expectedIdentity: nextIdentity,
      );
    }

    // The authoritative rotating credentials are one logical value.
    await _storage.write(key: _kTokenPair, value: encoded);
    final readback = await _storage.read(key: _kTokenPair);
    debugPrint(
      '[TokenStorage] writeTokens readback → '
      '${readback == encoded ? 'ok' : 'MISMATCH (write failed!)'}',
    );
    if (readback != encoded) {
      throw StateError('Secure token-pair write could not be verified');
    }

    try {
      if (!sameExactOwner) {
        // Keep a released legacy/split or previous-login rollback pair intact
        // until the authoritative successor is durable. Afterwards remove
        // access first, atomically overwrite refresh, then rebuild access.
        // Every interruption is therefore either an old coherent pair or a
        // refresh-only state, never cross-owner access + refresh. In
        // particular, do not delete the old refresh before overwriting it: a
        // failed successor write must retain one recoverable rollback token.
        await _deleteAndVerifyRollbackKey(_kAccessToken);
        await _writeAndVerifyRollbackToken(
          key: _kRefreshToken,
          token: refreshToken,
          expectedIdentity: nextIdentity,
        );
      }
      await _writeAndVerifyRollbackToken(
        key: _kAccessToken,
        token: accessToken,
        expectedIdentity: nextIdentity,
      );
      final mirror = AuthTokenSnapshot(
        accessToken: await _storage.read(key: _kAccessToken),
        refreshToken: await _storage.read(key: _kRefreshToken),
        storageFormat: AuthTokenStorageFormat.legacy,
      );
      if (mirror.identity != nextIdentity ||
          mirror.accessToken != accessToken ||
          mirror.refreshToken != refreshToken) {
        throw StateError(
          'Rollback token mirror has a mismatched session identity',
        );
      }
    } catch (error) {
      // The canonical one-key pair is already durable and verified. Mirror
      // maintenance exists only for rollback readers, so it must never make
      // the accepted login/refresh look failed and invite a duplicate OTP.
      debugPrint(
        '[TokenStorage] rollback mirror update deferred after canonical '
        'commit: $error',
      );
    }
  }

  Future<void> _deleteAndVerifyRollbackKey(String key) async {
    await _storage.delete(key: key);
    if (await _storage.read(key: key) != null) {
      throw StateError('Rollback token mirror delete could not be verified');
    }
  }

  Future<void> _writeAndVerifyRollbackToken({
    required String key,
    required String token,
    required AuthSessionIdentity? expectedIdentity,
  }) async {
    await _storage.write(key: key, value: token);
    final readback = await _storage.read(key: key);
    if (readback != token ||
        (expectedIdentity != null &&
            AuthSessionIdentity.tryParseJwt(readback) != expectedIdentity)) {
      throw StateError('Rollback token mirror write could not be verified');
    }
  }

  /// Prove existing auth/cache values are readable before publishing a newly
  /// accepted login. Android backup corruption is repaired here, before the
  /// new session exists. Once replacement starts, write failures must leave a
  /// readable prior session and cache untouched rather than calling deleteAll.
  Future<AuthTokenSnapshot>
      _prepareForAcceptedTokenReplacementUnlocked() async {
    try {
      final current = await _readRawTokenSnapshotUnlocked();
      // Always preflight the rollback mirror too. A permanent Android
      // credential-store failure must be resolved before publishing the new
      // versioned pair, never during its post-commit mirror.
      await _read(_kAccessToken);
      await _read(_kRefreshToken);
      await _read(_kRefreshAttempt);
      await _read(_kExplicitLogoutFence);
      _credentialResetAttemptedForCurrentFailure = false;
      return current;
    } catch (error, stackTrace) {
      if (!_recoverOnFailure || !_isPermanentCryptoFailure(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (_credentialResetAttemptedForCurrentFailure) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      _credentialResetAttemptedForCurrentFailure = true;
      debugPrint(
        '[TokenStorage] accepted-login credential preflight proved an '
        'unrecoverable Android master-key state; resetting once: $error',
      );
      try {
        await _storage.deleteAll();
        for (final key in const [
          _kTokenPair,
          _kAccessToken,
          _kRefreshToken,
          _kRefreshAttempt,
          _kExplicitLogoutFence,
        ]) {
          if (await _storage.read(key: key) != null) {
            throw StateError('Credential-store reset left $key populated');
          }
        }
      } catch (resetError) {
        debugPrint(
          '[TokenStorage] credential-store reset failed: $resetError',
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
      return const AuthTokenSnapshot.empty();
    }
  }

  Future<AuthTokenSnapshot> _readRawTokenSnapshotUnlocked() async {
    final encoded = await _read(_kTokenPair);
    if (encoded != null) {
      try {
        final pair = _decodeTokenPair(encoded);
        return AuthTokenSnapshot(
          accessToken: pair.accessToken,
          refreshToken: pair.refreshToken,
          storageFormat: AuthTokenStorageFormat.versioned,
        );
      } on Object catch (error) {
        // Never resurrect older credentials when a newer versioned record is
        // present but malformed. Bootstrap will keep the user in saved-session
        // recovery and a normal authenticated retry cannot use this state.
        throw StateError('Stored token pair is unreadable: $error');
      }
    }

    final legacyAccess = await _read(_kAccessToken);
    final legacyRefresh = await _read(_kRefreshToken);
    final accessToken =
        legacyAccess == null || legacyAccess.isEmpty ? null : legacyAccess;
    final refreshToken =
        legacyRefresh == null || legacyRefresh.isEmpty ? null : legacyRefresh;
    if (accessToken == null && refreshToken == null) {
      return const AuthTokenSnapshot.empty();
    }

    return AuthTokenSnapshot(
      accessToken: accessToken,
      refreshToken: refreshToken,
      storageFormat: AuthTokenStorageFormat.legacy,
    );
  }

  Future<AuthTokenSnapshot> _readTokenSnapshotUnlocked() async {
    final snapshot = await _readRawTokenSnapshotUnlocked();
    final encodedFence = await _read(_kExplicitLogoutFence);
    if (encodedFence == null) return snapshot;
    final fence = _ExplicitLogoutFenceRecord.tryParse(encodedFence);
    // A present but unreadable logout fence fails closed. It can be replaced
    // only by a verified accepted-login write, never by a background reader.
    if (fence == null || fence.covers(snapshot)) {
      return const AuthTokenSnapshot.empty();
    }
    return snapshot;
  }

  @override
  Future<AuthTokenSnapshot> readTokenSnapshot() =>
      _serialized(_readTokenSnapshotUnlocked);

  @override
  Future<String?> readAccessToken() async {
    final snapshot = await readTokenSnapshot();
    final value = snapshot.accessToken;
    debugPrint(
      '[TokenStorage] read access_token → '
      '${value == null ? 'null' : 'present(${value.length})'}',
    );
    return value;
  }

  @override
  Future<String?> readRefreshToken() async {
    final snapshot = await readTokenSnapshot();
    final value = snapshot.refreshToken;
    debugPrint(
      '[TokenStorage] read refresh_token → '
      '${value == null ? 'null' : 'present(${value.length})'}',
    );
    return value;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final accepted = AuthTokenSnapshot(
      accessToken: accessToken,
      refreshToken: refreshToken,
      storageFormat: AuthTokenStorageFormat.versioned,
    );
    if (accepted.identity == null) {
      throw StateError(
        'Accepted token pair has an unknown or mixed session identity',
      );
    }
    debugPrint(
      '[TokenStorage] writeTokens '
      '(access=${accessToken.length} refresh=${refreshToken.length})',
    );
    await _serialized(() async {
      final previous = await _prepareForAcceptedTokenReplacementUnlocked();
      await _writeTokenPairUnlocked(
        accessToken: accessToken,
        refreshToken: refreshToken,
        previous: previous,
      );
      // Only an accepted login may supersede an explicit-logout fence. The
      // canonical full pair is already durable and verified at this point.
      final encodedFence = await _read(_kExplicitLogoutFence);
      if (encodedFence != null) {
        Object? deleteError;
        StackTrace? deleteStackTrace;
        try {
          await _delete(_kExplicitLogoutFence);
        } catch (error, stackTrace) {
          deleteError = error;
          deleteStackTrace = stackTrace;
        }
        final remainingFence = await _read(_kExplicitLogoutFence);
        if (remainingFence != null) {
          final fence = _ExplicitLogoutFenceRecord.tryParse(remainingFence);
          final successor = await _readRawTokenSnapshotUnlocked();
          if (fence == null || fence.covers(successor)) {
            if (deleteError != null) {
              Error.throwWithStackTrace(deleteError, deleteStackTrace!);
            }
            throw StateError(
              'Accepted login is durable but its logout fence remains active',
            );
          }
          debugPrint(
            '[TokenStorage] stale explicit-logout fence cleanup deferred; '
            'verified accepted login is not covered',
          );
        }
      }
      _credentialResetAttemptedForCurrentFailure = false;
    });
  }

  @override
  Future<AuthExplicitLogoutFence?> beginExplicitLogout() {
    return _serialized(() async {
      final owner = await _readRawTokenSnapshotUnlocked();
      if (!owner.hasCredentials) return null;
      final principal = owner.principal;
      final generation = owner.generation;
      final record = _ExplicitLogoutFenceRecord(
        id: _uuid.v4(),
        subject: principal?.subject,
        role: principal?.role,
        sessionId: generation?.sessionId,
        roleAccountId: owner.carriedRoleAccountId,
        accessDigest: owner.accessToken == null
            ? null
            : refreshTokenDigest(owner.accessToken!),
        refreshDigest: owner.refreshToken == null
            ? null
            : refreshTokenDigest(owner.refreshToken!),
      );
      final encoded = jsonEncode(record.toJson());
      await _write(_kExplicitLogoutFence, encoded);
      if (await _read(_kExplicitLogoutFence) != encoded) {
        throw StateError('Explicit-logout fence could not be verified');
      }
      return AuthExplicitLogoutFence(id: record.id, owner: owner);
    });
  }

  Future<_ExplicitLogoutFenceRecord?> _currentExplicitLogoutFenceUnlocked(
    AuthExplicitLogoutFence fence,
  ) async {
    final encoded = await _read(_kExplicitLogoutFence);
    if (encoded == null) return null;
    final record = _ExplicitLogoutFenceRecord.tryParse(encoded);
    return record?.id == fence.id ? record : null;
  }

  @override
  Future<AuthTokenSnapshot?> readExplicitLogoutOwner(
    AuthExplicitLogoutFence fence,
  ) {
    return _serialized(() async {
      final record = await _currentExplicitLogoutFenceUnlocked(fence);
      if (record == null) return null;
      final current = await _readRawTokenSnapshotUnlocked();
      return record.covers(current) ? current : null;
    });
  }

  bool _isValidExplicitLogoutSuccessor(
    AuthTokenSnapshot expected,
    AuthSessionIdentity successor,
  ) {
    final exactIdentity = expected.identity;
    if (exactIdentity != null) return successor == exactIdentity;
    if (expected.isPreSessionIdCredentialState) {
      return successor.principal == expected.principal;
    }
    final expectedGeneration = expected.isInterruptedPreSessionIdUpgrade
        ? expected.accessLineage?.generation
        : expected.isSessionRoleAccountIdUpgrade
            ? expected.generation
            : null;
    if (expectedGeneration == null ||
        successor.generation != expectedGeneration) {
      return false;
    }
    final carriedRoleAccountId = expected.carriedRoleAccountId;
    return carriedRoleAccountId == null ||
        successor.roleAccountId == carriedRoleAccountId;
  }

  @override
  Future<bool> replaceExplicitLogoutTokensIfCurrent({
    required AuthExplicitLogoutFence fence,
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  }) {
    final accessIdentity = AuthSessionIdentity.tryParseJwt(accessToken);
    final refreshIdentity = AuthSessionIdentity.tryParseJwt(refreshToken);
    if (accessIdentity == null ||
        refreshIdentity != accessIdentity ||
        !_isValidExplicitLogoutSuccessor(expected, accessIdentity)) {
      return Future<bool>.value(false);
    }
    return _serialized(() async {
      final record = await _currentExplicitLogoutFenceUnlocked(fence);
      if (record == null) return false;
      final current = await _readRawTokenSnapshotUnlocked();
      if (!record.covers(current) ||
          !current.hasExactRawCredentials(expected)) {
        return false;
      }
      var evolvedRecord = record;
      if (record.sessionId == null) {
        evolvedRecord = _ExplicitLogoutFenceRecord(
          id: record.id,
          subject: record.subject,
          role: record.role,
          sessionId: accessIdentity.sessionId,
          roleAccountId: accessIdentity.roleAccountId,
          // Retain predecessor digests so a process death after the fence
          // evolves but before the canonical pair lands still hides A.
          accessDigest: record.accessDigest,
          refreshDigest: record.refreshDigest,
        );
        final encoded = jsonEncode(evolvedRecord.toJson());
        await _write(_kExplicitLogoutFence, encoded);
        if (await _read(_kExplicitLogoutFence) != encoded) {
          throw StateError(
            'Explicit-logout fence evolution could not be verified',
          );
        }
      }
      await _writeTokenPairUnlocked(
        accessToken: accessToken,
        refreshToken: refreshToken,
        previous: current,
      );
      final successor = await _readRawTokenSnapshotUnlocked();
      if (!evolvedRecord.covers(successor) ||
          successor.accessToken != accessToken ||
          successor.refreshToken != refreshToken) {
        throw StateError(
          'Explicit-logout repair escaped its durable session fence',
        );
      }
      return true;
    });
  }

  @override
  Future<bool> finishExplicitLogout(AuthExplicitLogoutFence fence) {
    return _serialized(() async {
      final record = await _currentExplicitLogoutFenceUnlocked(fence);
      if (record == null) return false;
      final current = await _readRawTokenSnapshotUnlocked();
      if (current.hasCredentials && !record.covers(current)) {
        // A separately accepted login became canonical. Remove only the stale
        // fence; its credentials and identity metadata belong to the new
        // owner and must survive this delayed logout completion.
        await _delete(_kExplicitLogoutFence);
        return false;
      }
      await _clearTokensUnlocked();
      return true;
    });
  }

  @override
  Future<String> readOrCreate(String refreshToken) {
    return _serialized(
      () => _readOrCreateRefreshAttemptUnlocked(refreshToken),
    );
  }

  @override
  Future<String?> readOrCreateIfCurrent(AuthTokenSnapshot expected) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return null;
      final refreshToken = expected.refreshToken;
      if (refreshToken == null) return null;
      return _readOrCreateRefreshAttemptUnlocked(refreshToken);
    });
  }

  Future<String> _readOrCreateRefreshAttemptUnlocked(
    String refreshToken,
  ) async {
    final tokenDigest = refreshTokenDigest(refreshToken);
    final raw = await _read(_kRefreshAttempt);
    if (raw != null) {
      try {
        final record = jsonDecode(raw);
        if (record is Map<String, dynamic> &&
            record['version'] == 1 &&
            record['refreshTokenDigest'] == tokenDigest &&
            record['attemptId'] is String &&
            isCanonicalRefreshAttemptId(record['attemptId'] as String)) {
          return record['attemptId'] as String;
        }
      } on FormatException {
        // Replace corrupt/non-current attempt metadata below.
      }
    }

    final attemptId = generateRefreshAttemptId();
    final encoded = jsonEncode({
      'version': 1,
      'refreshTokenDigest': tokenDigest,
      'attemptId': attemptId,
    });
    await _write(_kRefreshAttempt, encoded);
    if (await _read(_kRefreshAttempt) != encoded) {
      throw StateError(
        'Secure refresh-attempt persistence verification failed',
      );
    }
    return attemptId;
  }

  @override
  Future<void> clearIfMatches({
    required String refreshToken,
    required String attemptId,
  }) {
    return _serialized(() async {
      final raw = await _read(_kRefreshAttempt);
      if (raw == null) return;
      try {
        final record = jsonDecode(raw);
        if (record is Map<String, dynamic> &&
            record['version'] == 1 &&
            record['refreshTokenDigest'] == refreshTokenDigest(refreshToken) &&
            record['attemptId'] == attemptId) {
          await _delete(_kRefreshAttempt);
        }
      } on FormatException {
        // A corrupt record cannot match this completed attempt.
      }
    });
  }

  @override
  Future<bool> replaceTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  }) async {
    final expectedIdentity = expected.identity;
    final accessIdentity = AuthSessionIdentity.tryParseJwt(accessToken);
    final refreshIdentity = AuthSessionIdentity.tryParseJwt(refreshToken);
    if (expectedIdentity == null ||
        accessIdentity != expectedIdentity ||
        refreshIdentity != expectedIdentity) {
      debugPrint(
        '[TokenStorage] refusing token replacement with unknown/mixed '
        'session identity',
      );
      return false;
    }

    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.isExactCredentialState(expected)) return false;
      await _writeTokenPairUnlocked(
        accessToken: accessToken,
        refreshToken: refreshToken,
        previous: current,
      );
      return true;
    });
  }

  @override
  Future<bool> replaceLegacyTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  }) async {
    final expectedPrincipal = expected.principal;
    final accessIdentity = AuthSessionIdentity.tryParseJwt(accessToken);
    final refreshIdentity = AuthSessionIdentity.tryParseJwt(refreshToken);
    if (!expected.isPreSessionIdCredentialState ||
        expectedPrincipal == null ||
        accessIdentity == null ||
        refreshIdentity != accessIdentity ||
        accessIdentity.principal != expectedPrincipal) {
      debugPrint(
        '[TokenStorage] refusing legacy upgrade with unknown/mismatched '
        'account, role, or session identity',
      );
      return false;
    }

    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return false;
      await _writeTokenPairUnlocked(
        accessToken: accessToken,
        refreshToken: refreshToken,
        previous: current,
      );
      return true;
    });
  }

  @override
  Future<bool> replaceInterruptedLegacyTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  }) async {
    final proofGeneration = expected.accessLineage?.generation;
    final carriedRoleAccountId = expected.carriedRoleAccountId;
    final accessIdentity = AuthSessionIdentity.tryParseJwt(accessToken);
    final refreshIdentity = AuthSessionIdentity.tryParseJwt(refreshToken);
    if (!expected.isInterruptedPreSessionIdUpgrade ||
        proofGeneration == null ||
        accessIdentity == null ||
        refreshIdentity != accessIdentity ||
        accessIdentity.generation != proofGeneration ||
        (carriedRoleAccountId != null &&
            accessIdentity.roleAccountId != carriedRoleAccountId)) {
      debugPrint(
        '[TokenStorage] refusing interrupted legacy upgrade with '
        'mismatched account, role, or session identity',
      );
      return false;
    }

    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return false;
      await _writeTokenPairUnlocked(
        accessToken: accessToken,
        refreshToken: refreshToken,
        previous: current,
      );
      return true;
    });
  }

  @override
  Future<bool> replaceSessionLineageTokensIfCurrent({
    required AuthTokenSnapshot expected,
    required String accessToken,
    required String refreshToken,
  }) async {
    final expectedGeneration = expected.generation;
    final carriedRoleAccountId = expected.carriedRoleAccountId;
    final accessIdentity = AuthSessionIdentity.tryParseJwt(accessToken);
    final refreshIdentity = AuthSessionIdentity.tryParseJwt(refreshToken);
    if (!expected.isSessionRoleAccountIdUpgrade ||
        expectedGeneration == null ||
        accessIdentity == null ||
        refreshIdentity != accessIdentity ||
        accessIdentity.generation != expectedGeneration ||
        (carriedRoleAccountId != null &&
            accessIdentity.roleAccountId != carriedRoleAccountId)) {
      debugPrint(
        '[TokenStorage] refusing role-account lineage upgrade with '
        'mismatched private root, role, role account, or SID',
      );
      return false;
    }

    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return false;
      await _writeTokenPairUnlocked(
        accessToken: accessToken,
        refreshToken: refreshToken,
        previous: current,
      );
      return true;
    });
  }

  @override
  Future<void> writeAccessToken(String accessToken) async {
    debugPrint('[TokenStorage] writeAccessToken (len=${accessToken.length})');
    await _serialized(() async {
      final raw = await _readRawTokenSnapshotUnlocked();
      final encodedFence = await _read(_kExplicitLogoutFence);
      final fence = encodedFence == null
          ? null
          : _ExplicitLogoutFenceRecord.tryParse(encodedFence);
      if (encodedFence != null && (fence == null || fence.covers(raw))) {
        throw StateError(
          'Cannot mutate access credentials after explicit logout begins',
        );
      }
      final current = await _readTokenSnapshotUnlocked();
      final refreshToken = current.refreshToken;
      if (refreshToken == null) {
        await _write(_kAccessToken, accessToken);
        return;
      }
      await _writeTokenPairUnlocked(
        accessToken: accessToken,
        refreshToken: refreshToken,
        previous: current,
      );
    });
  }

  @override
  Future<void> clearTokens() async {
    debugPrint(
      '[TokenStorage] clearTokens — called from:\n${StackTrace.current}',
    );
    await _serialized(_clearTokensUnlocked);
  }

  Future<void> _clearTokensUnlocked() async {
    await _clearAuthTokensUnlocked();
    await _delete(_kPhone);
    await _delete(_kRole);
    await _delete(_kLegacySessionStartedAt);
    await _delete(_kCachedProfile);
    // _kDeviceId is intentionally preserved — stable per install.
    // _kOnboardingSeen is also preserved.
  }

  @override
  Future<bool> clearTokensIfCurrent(AuthTokenSnapshot expected) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return false;
      await _clearTokensUnlocked();
      return true;
    });
  }

  @override
  Future<bool> clearTokensForIdentityIfCurrent(
    AuthSessionIdentity expectedIdentity,
  ) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.belongsTo(expectedIdentity)) return false;
      await _clearTokensUnlocked();
      return true;
    });
  }

  Future<void> _clearAuthTokensUnlocked() async {
    await _delete(_kTokenPair);
    await _delete(_kAccessToken);
    await _delete(_kRefreshToken);
    await _delete(_kRefreshAttempt);
    await _delete(_kExplicitLogoutFence);
  }

  @override
  Future<void> clearAuthTokensOnly() async {
    debugPrint('[TokenStorage] clearAuthTokensOnly');
    await _serialized(_clearAuthTokensUnlocked);
  }

  @override
  Future<bool> clearAuthTokensOnlyIfCurrent(AuthTokenSnapshot expected) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return false;
      await _clearAuthTokensUnlocked();
      return true;
    });
  }

  @override
  Future<bool> clearAuthTokensOnlyForIdentityIfCurrent(
    AuthSessionIdentity expectedIdentity,
  ) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.belongsTo(expectedIdentity)) return false;
      await _clearAuthTokensUnlocked();
      return true;
    });
  }

  @override
  Future<bool> writeSessionMetadataIfCurrent({
    required AuthTokenSnapshot expected,
    String? phone,
    String? role,
  }) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return false;
      if (role != null) {
        await _storage.write(key: _kRole, value: role);
      }
      if (phone != null && phone.isNotEmpty) {
        await _storage.write(key: _kPhone, value: phone);
      }
      return true;
    });
  }

  @override
  Future<String?> readDeviceId() => _serialized(() => _read(_kDeviceId));

  @override
  Future<void> writeDeviceId(String deviceId) =>
      _serialized(() => _write(_kDeviceId, deviceId));

  @override
  Future<String?> readCachedProfileJson() =>
      _serialized(() => _storage.read(key: _kCachedProfile));

  @override
  Future<void> writeCachedProfileJson(String json) =>
      _serialized(() => _storage.write(key: _kCachedProfile, value: json));

  @override
  Future<bool> writeCachedProfileJsonIfCurrent({
    required AuthSessionIdentity expectedIdentity,
    required String json,
  }) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.belongsTo(expectedIdentity)) return false;
      await _storage.write(key: _kCachedProfile, value: json);
      return true;
    });
  }

  @override
  Future<void> clearCachedProfile() =>
      _serialized(() => _storage.delete(key: _kCachedProfile));

  @override
  Future<bool> clearCachedProfileIfCurrent(AuthTokenSnapshot expected) {
    return _serialized(() async {
      final current = await _readTokenSnapshotUnlocked();
      if (!current.hasExactRawCredentials(expected)) return false;
      await _storage.delete(key: _kCachedProfile);
      return true;
    });
  }

  @override
  Future<String?> readRole() => _serialized(() => _read(_kRole));

  @override
  Future<void> writeRole(String role) =>
      _serialized(() => _write(_kRole, role));

  @override
  Future<String?> readPhone() => _serialized(() => _read(_kPhone));

  @override
  Future<void> writePhone(String phone) =>
      _serialized(() => _write(_kPhone, phone));

  @override
  Future<bool> hasSeenOnboarding() async {
    final value = await _serialized(() => _read(_kOnboardingSeen));
    return value == 'true';
  }

  @override
  Future<void> markOnboardingSeen() =>
      _serialized(() => _write(_kOnboardingSeen, 'true'));
}
