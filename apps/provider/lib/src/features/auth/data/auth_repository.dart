import 'package:api_client/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [AuthService] with token persistence via secure storage.
class AuthRepository {
  AuthRepository({
    required AuthService service,
    FlutterSecureStorage? storage,
  })  : _service = service,
        _storage = storage ?? const FlutterSecureStorage();

  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';
  static const _kPhone = 'auth_phone';

  final AuthService _service;
  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);
  Future<String?> readPhone() => _storage.read(key: _kPhone);

  Future<void> _persistTokens({
    required String accessToken,
    required String refreshToken,
    required String phone,
  }) async {
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
    await _storage.write(key: _kPhone, value: phone);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kPhone);
  }

  Future<OtpRequestResult> requestOtp(String phone) =>
      _service.requestOtp(phone);

  Future<OtpVerifyResult> verifyOtp({
    required String otpId,
    required String code,
    required String phone,
  }) async {
    final result = await _service.verifyOtp(otpId: otpId, code: code);
    await _persistTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      phone: phone,
    );
    return result;
  }

  Future<AuthUser> registerDriver({
    required String phone,
    required DriverRegistrationPayload payload,
  }) async {
    final token = await readAccessToken();
    if (token == null) throw AuthException('No active session.');
    return _service.registerDriver(
      accessToken: token,
      phone: phone,
      payload: payload,
    );
  }

  Future<AuthUser> registerArtisan({
    required String phone,
    required ArtisanRegistrationPayload payload,
  }) async {
    final token = await readAccessToken();
    if (token == null) throw AuthException('No active session.');
    return _service.registerArtisan(
      accessToken: token,
      phone: phone,
      payload: payload,
    );
  }

  Future<AuthUser?> bootstrap() async {
    final token = await readAccessToken();
    if (token == null) return null;
    return _service.currentUser(token);
  }
}
