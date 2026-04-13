import 'package:dio/dio.dart';

import '../models/auth_dtos.dart';
import 'token_storage.dart';

/// Interceptor that:
/// 1. Injects the Bearer token on every authenticated request.
/// 2. Automatically refreshes the access token on 401 responses.
/// 3. Emits a logout signal when the refresh token is also expired.
///
/// Uses [QueuedInterceptor] so that concurrent 401s don't trigger
/// multiple refresh calls — the first 401 refreshes, the rest wait.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required TokenStorage tokenStorage,
    required Dio dio,
    void Function()? onForceLogout,
  })  : _tokenStorage = tokenStorage,
        _dio = dio,
        _onForceLogout = onForceLogout;

  final TokenStorage _tokenStorage;
  final Dio _dio;
  final void Function()? _onForceLogout;

  /// Paths that do not require an Authorization header.
  static const _publicPaths = {
    '/auth/register',
    '/auth/login/client',
    '/auth/login/driver',
    '/auth/login/artisan',
    '/auth/verify-otp',
    '/auth/refresh',
    '/auth/recover',
    '/config/',
    '/surge/current',
  };

  bool _isPublic(String path) {
    return _publicPaths.any((p) => path.contains(p));
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPublic(options.path)) {
      final token = await _tokenStorage.readAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;

    // Only attempt refresh on 401 for authenticated endpoints
    if (response?.statusCode != 401 || _isPublic(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    // Try to refresh the access token
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken == null) {
        _onForceLogout?.call();
        handler.next(err);
        return;
      }

      final refreshResponse = await _dio.post(
        '/auth/refresh',
        data: RefreshRequest(refreshToken: refreshToken).toJson(),
      );

      final data = refreshResponse.data as Map<String, dynamic>;
      final newAccessToken = data['data']?['accessToken'] as String? ??
          data['accessToken'] as String;

      await _tokenStorage.writeAccessToken(newAccessToken);

      // Retry the original request with the new token
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';

      final retryResponse = await _dio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } on DioException catch (refreshError) {
      // Refresh failed — token expired or session inactive
      final code = refreshError.response?.data;
      if (code is Map<String, dynamic>) {
        final errorCode = (code['error'] as Map<String, dynamic>?)?['code'];
        if (errorCode == 'TOKEN_EXPIRED' ||
            errorCode == 'INVALID_TOKEN' ||
            errorCode == 'SESSION_INACTIVE' ||
            errorCode == 'USER_NOT_FOUND') {
          await _tokenStorage.clearTokens();
          _onForceLogout?.call();
        }
      }
      handler.next(err);
    } catch (_) {
      handler.next(err);
    }
  }
}
