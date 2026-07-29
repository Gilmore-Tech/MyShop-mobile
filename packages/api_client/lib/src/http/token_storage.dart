import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'refresh_attempt_store.dart';

/// How long a stored session is trusted before forcing the user to re-login,
/// regardless of backend token expiry. Lets providers stay signed-in across
/// app restarts so they keep receiving requests in the background.
const Duration kSessionTtl = Duration(days: 7);

/// Abstract interface for token persistence.
/// Keeps the HTTP layer testable without Flutter dependencies.
abstract class TokenStorage {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> writeAccessToken(String accessToken);

  /// Wipe everything tied to the user's identity — tokens, phone, role,
  /// session timestamp, cached profile. Used when the backend tells us the
  /// session is fundamentally dead (TOKEN_EXPIRED / INVALID_TOKEN /
  /// REFRESH_TOKEN_REUSED) or the user explicitly logs out.
  ///
  /// The persistent device ID is preserved across this call — it represents
  /// the install, not the user.
  Future<void> clearTokens();

  /// Wipe ONLY the JWT pair, preserving phone, role, cached profile, and
  /// session start. Used for SESSION_TAKEN_OVER: the current tokens are
  /// invalidated server-side but the user's identity context is still
  /// useful for a quick re-login on the same device.
  Future<void> clearAuthTokensOnly();

  Future<String?> readPhone();
  Future<void> writePhone(String phone);

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

  /// When the current session was established (i.e. the last successful OTP
  /// verification). Used to enforce [kSessionTtl] on bootstrap.
  Future<DateTime?> readSessionStartedAt();
  Future<void> writeSessionStartedAt(DateTime when);

  /// Cached `/users/me` response JSON. Lets bootstrap restore the
  /// authenticated UI when the device is offline at app start.
  Future<String?> readCachedProfileJson();
  Future<void> writeCachedProfileJson(String json);
}

/// Production implementation backed by Flutter Secure Storage
/// (Keychain on iOS, EncryptedSharedPreferences on Android).
class SecureTokenStorage implements TokenStorage, RefreshAttemptStore {
  SecureTokenStorage([
    FlutterSecureStorage? storage,
    bool? recoverOnFailure,
  ])  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            ),
        _recoverOnFailure =
            recoverOnFailure ?? defaultTargetPlatform == TargetPlatform.android;

  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';
  static const _kPhone = 'auth_phone';
  static const _kOnboardingSeen = 'onboarding_seen';
  static const _kRole = 'auth_role';
  static const _kSessionStartedAt = 'auth_session_started_at';
  static const _kCachedProfile = 'auth_cached_profile';
  static const _kDeviceId = 'auth_device_id';
  static const _kRefreshAttempt = 'auth_refresh_attempt_v1';

  final FlutterSecureStorage _storage;
  final bool _recoverOnFailure;

  /// Android Auto Backup can restore encrypted preferences without the
  /// Keystore key that encrypted them. In that state every secure-storage
  /// access throws before login can reach the API. Clear the unreadable store
  /// once and retry so the user can establish a fresh session.
  Future<T> _withRecovery<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      if (!_recoverOnFailure) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      debugPrint(
        '[TokenStorage] $operation failed; clearing unreadable Android '
        'secure storage and retrying: $error',
      );
      try {
        await _storage.deleteAll();
      } catch (clearError) {
        debugPrint('[TokenStorage] recovery deleteAll failed: $clearError');
        Error.throwWithStackTrace(error, stackTrace);
      }
      return action();
    }
  }

  Future<String?> _read(String key) =>
      _withRecovery('read $key', () => _storage.read(key: key));

  Future<void> _write(String key, String value) => _withRecovery(
        'write $key',
        () => _storage.write(key: key, value: value),
      );

  Future<void> _delete(String key) =>
      _withRecovery('delete $key', () => _storage.delete(key: key));

  @override
  Future<String?> readAccessToken() async {
    final value = await _read(_kAccessToken);
    debugPrint(
      '[TokenStorage] read access_token → ${value == null ? 'null' : 'present(${value.length})'}',
    );
    return value;
  }

  @override
  Future<String?> readRefreshToken() async {
    final value = await _read(_kRefreshToken);
    debugPrint(
      '[TokenStorage] read refresh_token → ${value == null ? 'null' : 'present(${value.length})'}',
    );
    return value;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    debugPrint(
      '[TokenStorage] writeTokens (access=${accessToken.length} refresh=${refreshToken.length})',
    );
    await _withRecovery('write tokens', () async {
      await _storage.write(key: _kAccessToken, value: accessToken);
      await _storage.write(key: _kRefreshToken, value: refreshToken);
      // Read back to verify the write actually landed. On iOS simulator
      // keychain can silently swallow writes in some configurations; this
      // turns that into a loud log line instead of a mysterious logout.
      final accessReadback = await _storage.read(key: _kAccessToken);
      final refreshReadback = await _storage.read(key: _kRefreshToken);
      debugPrint(
        '[TokenStorage] writeTokens readback → '
        '${accessReadback == accessToken && refreshReadback == refreshToken ? 'ok' : 'MISMATCH'}',
      );
      if (accessReadback != accessToken || refreshReadback != refreshToken) {
        throw StateError('Secure token-pair persistence verification failed');
      }
    });
  }

  @override
  Future<String> readOrCreate(String refreshToken) async {
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
        // Replace corrupt/non-current metadata without touching auth tokens.
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
  }) async {
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
      // A corrupt record cannot match this completed attempt. The next refresh
      // replaces it before sending a request.
    }
  }

  @override
  Future<void> writeAccessToken(String accessToken) async {
    debugPrint('[TokenStorage] writeAccessToken (len=${accessToken.length})');
    await _write(_kAccessToken, accessToken);
  }

  @override
  Future<void> clearTokens() async {
    debugPrint(
      '[TokenStorage] clearTokens — called from:\n${StackTrace.current}',
    );
    await _delete(_kAccessToken);
    await _delete(_kRefreshToken);
    await _delete(_kPhone);
    await _delete(_kRole);
    await _delete(_kSessionStartedAt);
    await _delete(_kCachedProfile);
    await _delete(_kRefreshAttempt);
    // _kDeviceId is intentionally preserved — stable per install.
    // _kOnboardingSeen is also preserved.
  }

  @override
  Future<void> clearAuthTokensOnly() async {
    debugPrint('[TokenStorage] clearAuthTokensOnly');
    await _delete(_kAccessToken);
    await _delete(_kRefreshToken);
    await _delete(_kRefreshAttempt);
  }

  @override
  Future<String?> readDeviceId() => _read(_kDeviceId);

  @override
  Future<void> writeDeviceId(String deviceId) => _write(_kDeviceId, deviceId);

  @override
  Future<DateTime?> readSessionStartedAt() async {
    final value = await _read(_kSessionStartedAt);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  @override
  Future<void> writeSessionStartedAt(DateTime when) =>
      _write(_kSessionStartedAt, when.toIso8601String());

  @override
  Future<String?> readCachedProfileJson() => _read(_kCachedProfile);

  @override
  Future<void> writeCachedProfileJson(String json) =>
      _write(_kCachedProfile, json);

  @override
  Future<String?> readRole() => _read(_kRole);

  @override
  Future<void> writeRole(String role) => _write(_kRole, role);

  @override
  Future<String?> readPhone() => _read(_kPhone);

  @override
  Future<void> writePhone(String phone) => _write(_kPhone, phone);

  @override
  Future<bool> hasSeenOnboarding() async {
    final value = await _read(_kOnboardingSeen);
    return value == 'true';
  }

  @override
  Future<void> markOnboardingSeen() => _write(_kOnboardingSeen, 'true');
}
