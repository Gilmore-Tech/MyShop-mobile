import 'package:dio/dio.dart';

import '../http/auth_interceptor.dart';
import '../http/token_storage.dart';
import '../models/api_exception.dart';
import '../models/auth_dtos.dart';
import '../models/user_dtos.dart';
import 'auth_service.dart';

/// Production [AuthService] backed by Dio HTTP calls to the MyShop API.
class RealAuthService implements AuthService {
  RealAuthService(this._dio);

  final Dio _dio;

  /// Unwraps the standard `{ success, data, error }` envelope.
  /// Throws [ApiException] on non-success responses.
  dynamic _unwrap(Response response) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) return body['data'];
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }

  @override
  Future<void> register(RegisterRequest request) async {
    try {
      await _dio.post('/auth/register', data: request.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> loginDriver(LoginRequest request) async {
    try {
      await _dio.post('/auth/login/driver', data: request.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> loginArtisan(LoginRequest request) async {
    try {
      await _dio.post('/auth/login/artisan', data: request.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> loginClient(LoginRequest request) async {
    try {
      await _dio.post('/auth/login/client', data: request.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<List<String>> checkPhone(String phone) async {
    try {
      final response = await _dio.post(
        '/auth/check-phone',
        data: PhoneOnlyRequest(phone: phone).toJson(),
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      final roles = (data['roles'] as List).cast<String>();
      return roles;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<String> login(LoginRequest request) async {
    final data = request.toJson();
    // Try driver first, then artisan.
    try {
      await _dio.post('/auth/login/driver', data: data);
      return 'driver';
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        throw ApiException.fromDioException(e);
      }
    }
    try {
      await _dio.post('/auth/login/artisan', data: data);
      return 'artisan';
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> logout({
    AuthSessionIdentity? expectedIdentity,
    AuthTokenSnapshot? explicitLogoutSession,
  }) async {
    try {
      await _dio.post(
        '/auth/logout',
        options: expectedIdentity == null && explicitLogoutSession == null
            ? null
            : Options(
                extra: {
                  if (expectedIdentity != null)
                    AuthInterceptor.expectedSessionIdentityExtra:
                        expectedIdentity,
                  if (explicitLogoutSession != null)
                    AuthInterceptor.explicitLogoutSessionExtra:
                        explicitLogoutSession,
                },
              ),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> requestSessionRecovery({
    required String challenge,
    required String phone,
    required String deviceId,
    required String role,
  }) async {
    try {
      await _dio.post(
        '/auth/request-session-recovery',
        data: SessionRecoveryRequest(
          challenge: challenge,
          phone: phone,
          deviceId: deviceId,
          role: role,
        ).toJson(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> requestRoleAccountRecoveryOtp(
    RequestRoleAccountRecoveryOtpRequest request,
  ) async {
    try {
      await _dio.post(
        '/auth/role-account-recovery/request-otp',
        data: request.toJson(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<RoleAccountRecoveryResult> verifyRoleAccountRecoveryOtp(
    VerifyRoleAccountRecoveryOtpRequest request,
  ) async {
    try {
      final response = await _dio.post(
        '/auth/role-account-recovery/verify-otp',
        data: request.toJson(),
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      return RoleAccountRecoveryResult.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<TokenResponse> verifyOtp(VerifyOtpRequest request) async {
    try {
      final response = await _dio.post(
        '/auth/verify-otp',
        data: request.toJson(),
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      return TokenResponse.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<List<String>> getOtpChannels() async {
    try {
      final response = await _dio.get('/auth/otp/channels');
      final data = _unwrap(response) as Map<String, dynamic>;
      return (data['available'] as List<dynamic>)
          .whereType<String>()
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> resendOtp({
    required String phone,
    required String channel,
  }) async {
    try {
      await _dio.post(
        '/auth/otp/resend',
        data: {'phone': phone, 'channel': channel},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> providerLogin(LoginRequest request) async {
    try {
      await _dio.post('/auth/provider/login', data: request.toJson());
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<ProviderVerifyResult> providerVerifyOtp(
    ProviderVerifyOtpRequest request,
  ) async {
    try {
      final response = await _dio.post(
        '/auth/provider/verify-otp',
        data: request.toJson(),
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      return ProviderVerifyResult.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<ProviderSession> providerSelectRole(
    ProviderSelectRoleRequest request,
  ) async {
    try {
      final response = await _dio.post(
        '/auth/provider/select-role',
        data: request.toJson(),
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      return ProviderSession.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<UserProfile> getMe() async {
    try {
      final response = await _dio.get('/users/me');
      final data = _unwrap(response) as Map<String, dynamic>;
      return UserProfile.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<({UserProfile profile, Map<String, dynamic> raw})>
      getMeWithRaw() async {
    try {
      final response = await _dio.get('/users/me');
      final data = _unwrap(response) as Map<String, dynamic>;
      return (profile: UserProfile.fromJson(data), raw: data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<UserProfile> updateMe(UpdateProfileRequest request) async {
    try {
      final response = await _dio.put('/users/me', data: request.toJson());
      final data = _unwrap(response) as Map<String, dynamic>;
      return UserProfile.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<UserProfile> updateDriver(UpdateDriverProfileRequest request) async {
    try {
      final response =
          await _dio.put('/users/me/driver', data: request.toJson());
      final data = _unwrap(response) as Map<String, dynamic>;
      return UserProfile.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<UserProfile> updateArtisan(UpdateArtisanProfileRequest request) async {
    try {
      final response =
          await _dio.put('/users/me/artisan', data: request.toJson());
      final data = _unwrap(response) as Map<String, dynamic>;
      return UserProfile.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
