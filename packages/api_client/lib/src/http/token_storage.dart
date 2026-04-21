import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  Future<void> clearTokens();
  Future<String?> readPhone();
  Future<void> writePhone(String phone);

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
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';
  static const _kPhone = 'auth_phone';
  static const _kOnboardingSeen = 'onboarding_seen';
  static const _kRole = 'auth_role';
  static const _kSessionStartedAt = 'auth_session_started_at';
  static const _kCachedProfile = 'auth_cached_profile';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
  }

  @override
  Future<void> writeAccessToken(String accessToken) =>
      _storage.write(key: _kAccessToken, value: accessToken);

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kPhone);
    await _storage.delete(key: _kRole);
    await _storage.delete(key: _kSessionStartedAt);
    await _storage.delete(key: _kCachedProfile);
  }

  @override
  Future<DateTime?> readSessionStartedAt() async {
    final value = await _storage.read(key: _kSessionStartedAt);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  @override
  Future<void> writeSessionStartedAt(DateTime when) =>
      _storage.write(key: _kSessionStartedAt, value: when.toIso8601String());

  @override
  Future<String?> readCachedProfileJson() =>
      _storage.read(key: _kCachedProfile);

  @override
  Future<void> writeCachedProfileJson(String json) =>
      _storage.write(key: _kCachedProfile, value: json);

  @override
  Future<String?> readRole() => _storage.read(key: _kRole);

  @override
  Future<void> writeRole(String role) =>
      _storage.write(key: _kRole, value: role);

  @override
  Future<String?> readPhone() => _storage.read(key: _kPhone);

  @override
  Future<void> writePhone(String phone) =>
      _storage.write(key: _kPhone, value: phone);

  @override
  Future<bool> hasSeenOnboarding() async {
    final value = await _storage.read(key: _kOnboardingSeen);
    return value == 'true';
  }

  @override
  Future<void> markOnboardingSeen() =>
      _storage.write(key: _kOnboardingSeen, value: 'true');
}
