import 'package:dio/dio.dart';

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
  Future<void> loginDriver(String phone) async {
    try {
      await _dio.post(
        '/auth/login/driver',
        data: LoginRequest(phone: phone).toJson(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<void> loginArtisan(String phone) async {
    try {
      await _dio.post(
        '/auth/login/artisan',
        data: LoginRequest(phone: phone).toJson(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<List<String>> checkPhone(String phone) async {
    try {
      final response = await _dio.post(
        '/auth/check-phone',
        data: LoginRequest(phone: phone).toJson(),
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      final roles = (data['roles'] as List).cast<String>();
      return roles;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  @override
  Future<String> login(String phone) async {
    final data = LoginRequest(phone: phone).toJson();
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
  Future<String> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: RefreshRequest(refreshToken: refreshToken).toJson(),
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      return RefreshResponse.fromJson(data).accessToken;
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
