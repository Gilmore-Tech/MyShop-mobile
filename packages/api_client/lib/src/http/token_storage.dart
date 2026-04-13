import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  /// Whether the user has completed the onboarding/welcome screen at least
  /// once. Survives logout — only a full app data clear resets this.
  Future<bool> hasSeenOnboarding();
  Future<void> markOnboardingSeen();
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
  }

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
