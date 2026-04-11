import 'auth_models.dart';
import 'auth_service.dart';

/// In-memory mock so the UI can be developed end-to-end before the backend
/// auth endpoints are live.
///
/// Behaviour:
///   - Any phone number is accepted.
///   - The OTP code is always `123456`.
///   - A phone is treated as an EXISTING user if it ends with `0000` —
///     verifyOtp returns a fully verified driver. Anything else is treated
///     as a NEW user (no profile yet) and the registration flow runs.
class MockAuthService implements AuthService {
  MockAuthService();

  static const _validCode = '123456';
  final Map<String, String> _otpToPhone = {};
  final Map<String, AuthUser> _usersByToken = {};
  int _seq = 0;

  @override
  Future<OtpRequestResult> requestOtp(String phone) async {
    await _delay();
    _seq++;
    final otpId = 'otp_$_seq';
    _otpToPhone[otpId] = phone;
    return OtpRequestResult(
      otpId: otpId,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<OtpVerifyResult> verifyOtp({
    required String otpId,
    required String code,
  }) async {
    await _delay();
    final phone = _otpToPhone[otpId];
    if (phone == null) {
      throw AuthException('OTP session expired. Please request a new code.');
    }
    if (code != _validCode) {
      throw AuthException('Invalid OTP code.');
    }
    final token = 'tok_$_seq';
    final isExisting = phone.endsWith('0000');
    AuthUser? user;
    if (isExisting) {
      user = AuthUser(
        id: 'usr_${phone.hashCode}',
        phone: phone,
        role: AuthRole.driver,
        fullName: 'Returning Driver',
        isVerified: true,
      );
      _usersByToken[token] = user;
    }
    return OtpVerifyResult(
      accessToken: token,
      refreshToken: 'refresh_$token',
      isNewUser: !isExisting,
      user: user,
    );
  }

  @override
  Future<AuthUser> registerDriver({
    required String accessToken,
    required String phone,
    required DriverRegistrationPayload payload,
  }) async {
    await _delay();
    final user = AuthUser(
      id: 'usr_${phone.hashCode}',
      phone: phone,
      role: AuthRole.driver,
      fullName: payload.fullName,
      isVerified: false,
    );
    _usersByToken[accessToken] = user;
    return user;
  }

  @override
  Future<AuthUser> registerArtisan({
    required String accessToken,
    required String phone,
    required ArtisanRegistrationPayload payload,
  }) async {
    await _delay();
    final user = AuthUser(
      id: 'usr_${phone.hashCode}',
      phone: phone,
      role: AuthRole.artisan,
      fullName: payload.fullName,
      isVerified: false,
    );
    _usersByToken[accessToken] = user;
    return user;
  }

  @override
  Future<AuthUser?> currentUser(String accessToken) async {
    await _delay();
    return _usersByToken[accessToken];
  }

  Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 600));
}
