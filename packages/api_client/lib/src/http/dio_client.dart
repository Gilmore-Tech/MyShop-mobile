import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'auth_interceptor.dart';
import 'logging_interceptor.dart';
import 'token_storage.dart';

/// Creates a fully configured [Dio] instance with auth, logging, and
/// error interceptors.
///
/// [onForceLogout] is called when both access and refresh tokens are
/// invalid — the app should redirect to the login screen.
Dio createDioClient({
  required ApiConfig config,
  required TokenStorage tokenStorage,
  void Function()? onForceLogout,
  bool enableLogging = true,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Order matters: logging first (sees raw request), then auth
  if (enableLogging) {
    dio.interceptors.add(LoggingInterceptor());
  }

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: tokenStorage,
      dio: dio,
      onForceLogout: onForceLogout,
    ),
  );

  return dio;
}
