import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'auth_interceptor.dart';
import 'logging_interceptor.dart';
import 'token_refresher.dart';
import 'token_storage.dart';

/// Bundle returned by [createDioClient] — the configured [Dio] plus the
/// shared [TokenRefresher] that both REST and WS layers must use for
/// `/auth/refresh` so they don't race the same rotating refresh token.
class DioClient {
  const DioClient({required this.dio, required this.refresher});

  final Dio dio;
  final TokenRefresher refresher;
}

/// Creates a fully configured [Dio] instance with auth, logging, and
/// error interceptors, plus the shared [TokenRefresher] that the WS
/// socket service must reuse.
///
/// [onForceLogout] is called when both access and refresh tokens are
/// invalid — the app should redirect to the login screen.
DioClient createDioClient({
  required ApiConfig config,
  required TokenStorage tokenStorage,
  void Function()? onForceLogout,
  bool enableLogging = true,
  // Identifies the calling app on every request (e.g. 'myshop-provider/1.2.0').
  // Lets the Cloudflare WAF drop scripted traffic to /auth that doesn't look
  // like the app (see docs/cloudflare-edge-protection.md §5). Informational,
  // not a secret.
  String clientId = 'myshop-app',
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-MyShop-Client': clientId,
      },
    ),
  );

  // Order matters: logging first (sees raw request), then auth
  if (enableLogging) {
    dio.interceptors.add(LoggingInterceptor());
  }

  // The refresher shares this same Dio instance, so its `/auth/refresh`
  // posts go through the logging interceptor (visible) and through the
  // auth interceptor's onRequest — which skips public paths, leaving
  // the refresh request unmodified. Sharing one Dio is what lets the
  // refresher's single-flight actually coordinate concurrent callers.
  final refresher = TokenRefresher(
    dio: dio,
    tokenStorage: tokenStorage,
    onForceLogout: onForceLogout,
  );

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: tokenStorage,
      dio: dio,
      tokenRefresher: refresher,
      onForceLogout: onForceLogout,
    ),
  );

  return DioClient(dio: dio, refresher: refresher);
}
