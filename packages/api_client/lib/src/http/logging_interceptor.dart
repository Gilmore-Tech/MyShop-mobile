import 'package:api_client/mobile_diagnostics.dart' as developer;

import 'package:dio/dio.dart';

/// Development-only interceptor that logs HTTP request/response summaries.
/// Never logs authorization headers or token values.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    developer.debugLog(
      () => '→ ${options.method} ${options.path}',
      name: 'HTTP',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final ms = response.requestOptions.extra['_startTime'] != null
        ? DateTime.now()
            .difference(
              response.requestOptions.extra['_startTime'] as DateTime,
            )
            .inMilliseconds
            .toString()
        : '?';
    developer.debugLog(
      () => '← ${response.statusCode} ${response.requestOptions.method} '
          '${response.requestOptions.path} (${ms}ms)',
      name: 'HTTP',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    developer.debugLog(
      () => '✗ ${err.response?.statusCode ?? 'NETWORK'} '
          '${err.requestOptions.method} ${err.requestOptions.path} — '
          '${err.message}',
      name: 'HTTP',
      level: 900, // Warning level
    );
    handler.next(err);
  }
}
