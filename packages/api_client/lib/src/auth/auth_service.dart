import 'auth_models.dart';

/// Auth API contract. Implementations: [MockAuthService] for development,
/// real Dio-backed impl to follow when the backend is live.
abstract class AuthService {
  Future<OtpRequestResult> requestOtp(String phone);

  Future<OtpVerifyResult> verifyOtp({
    required String otpId,
    required String code,
  });

  Future<AuthUser> registerDriver({
    required String accessToken,
    required String phone,
    required DriverRegistrationPayload payload,
  });

  Future<AuthUser> registerArtisan({
    required String accessToken,
    required String phone,
    required ArtisanRegistrationPayload payload,
  });

  Future<AuthUser?> currentUser(String accessToken);
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}
