import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_error_mapper.dart';
import 'token_refresher.dart';
import 'token_storage.dart';

/// Interceptor that:
/// 1. Injects the Bearer token on every authenticated request.
/// 2. Handles 401 responses by refreshing via the shared
///    [TokenRefresher] and retrying. The refresher single-flights
///    `/auth/refresh` across every caller (REST 401, WS pre-connect,
///    WS UNAUTHORIZED), so concurrent paths don't race the same
///    rotating refresh token through the backend and one of them
///    eat a `REFRESH_TOKEN_REUSED`. A local stored-vs-attached token
///    check ALSO short-circuits the refresh when another caller has
///    already written a fresh access token between the request going
///    out and the 401 coming back.
/// 3. Emits a logout signal when the refresh token itself is dead —
///    owned entirely by [TokenRefresher].
///
/// Must extend plain [Interceptor], NOT [QueuedInterceptor]. Dio's
/// `QueuedInterceptor` serializes onError through a single queue per
/// instance; awaiting `/auth/refresh` from inside an onError handler
/// means the refresh's own onError (when the refresh itself returns
/// 4xx) gets queued behind the outer handler awaiting it —
/// deadlocking the chain. Plain [Interceptor] avoids that and the
/// concurrency we actually need is provided by [TokenRefresher].
///
/// We do not pre-refresh expired tokens in [onRequest]; the socket
/// layer handles proactive refresh (also via [TokenRefresher]), and
/// the REST path relies on the 401 → refresh round-trip.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStorage tokenStorage,
    required Dio dio,
    required TokenRefresher tokenRefresher,
    void Function()? onForceLogout,
  })  : _tokenStorage = tokenStorage,
        _dio = dio,
        _tokenRefresher = tokenRefresher,
        _onForceLogout = onForceLogout;

  final TokenStorage _tokenStorage;
  final Dio _dio;
  final TokenRefresher _tokenRefresher;
  final void Function()? _onForceLogout;

  /// Paths that do not require an Authorization header.
  static const _publicPaths = {
    '/auth/register',
    '/auth/check-phone',
    '/auth/login/client',
    '/auth/login/driver',
    '/auth/login/artisan',
    '/auth/verify-otp',
    '/auth/refresh',
    '/auth/recover',
    '/auth/request-session-recovery',
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
    if (_isPublic(options.path)) {
      handler.next(options);
      return;
    }

    final token = await _tokenStorage.readAccessToken();
    if (token == null) {
      // No token + non-public path = the user is signed out (or never
      // signed in). Reject the request locally with a `cancel` type so it
      // never hits the wire and so [onError] doesn't pattern-match it as
      // a real 401 and try to refresh against nothing. Background loops
      // that race with logout (e.g. the location heartbeat firing one
      // more tick after the user is wiped) used to generate a continuous
      // 401 storm here; this short-circuit ends them at source.
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'NOT_AUTHENTICATED',
          message: 'Authenticated request attempted without a token — '
              'session is over.',
        ),
      );
      return;
    }
    options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final path = err.requestOptions.path;

    if (response?.statusCode != 401 || _isPublic(path)) {
      handler.next(err);
      return;
    }

    // /auth/logout: a 401 here means our access token is already invalid,
    // which is fine — we're tearing down the session anyway. Don't try
    // to refresh (it might be hanging behind a slow /auth/refresh in the
    // queue, and even if it succeeded, we're about to wipe tokens). Just
    // propagate so the caller can move on.
    if (path.contains('/auth/logout')) {
      debugPrint('[Auth] 401 on /auth/logout — propagating (no refresh)');
      handler.next(err);
      return;
    }

    final errorCode = _extractErrorCode(response);

    // SESSION_TAKEN_OVER: another device claimed the session. Refreshing
    // will just produce another SESSION_TAKEN_OVER (refresh tokens were
    // invalidated server-side). Soft-logout immediately — clear the JWT
    // pair but preserve phone/role/cached profile so the user can sign
    // back in with one tap.
    if (errorCode == AuthErrorCodes.sessionTakenOver) {
      debugPrint('[Auth] SESSION_TAKEN_OVER on $path — soft logout');
      await _tokenStorage.clearAuthTokensOnly();
      _onForceLogout?.call();
      handler.next(err);
      return;
    }

    // REFRESH_IN_FLIGHT: backend's per-(userId, role) refresh lock saw a
    // concurrent /auth/refresh and rejected this one. The winning refresh
    // is racing to rotate tokens RIGHT NOW. Wait briefly, then retry the
    // ORIGINAL request — by then the stored access token has been
    // updated by the [TokenRefresher] callback and we just need to
    // re-attach it. Do NOT call _tokenRefresher.refresh() again; that
    // would just hit the lock a second time.
    if (errorCode == AuthErrorCodes.refreshInFlight) {
      debugPrint('[Auth] REFRESH_IN_FLIGHT on $path — backing off 250ms');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final freshToken = await _tokenStorage.readAccessToken();
      if (freshToken != null) {
        debugPrint('[Auth] retrying $path with refreshed token');
        await _retryWithToken(err.requestOptions, freshToken, handler);
        return;
      }
      // No fresh token after the backoff — propagate so the caller can
      // either surface the failure or trigger its own logout.
      debugPrint('[Auth] no fresh token after REFRESH_IN_FLIGHT backoff');
      handler.next(err);
      return;
    }

    debugPrint('[Auth] 401 on $path (code=$errorCode) — attempting refresh');

    // Dedup: if another concurrent 401 already refreshed the token, the
    // stored access token will differ from the one we sent. Just retry
    // with the fresh stored token — no need to refresh again.
    final attachedAuth =
        err.requestOptions.headers['Authorization']?.toString();
    final attachedToken =
        attachedAuth != null && attachedAuth.startsWith('Bearer ')
            ? attachedAuth.substring(7)
            : null;
    final currentStored = await _tokenStorage.readAccessToken();

    if (currentStored != null &&
        attachedToken != null &&
        currentStored != attachedToken) {
      debugPrint('[Auth] another request already refreshed — retrying $path');
      await _retryWithToken(err.requestOptions, currentStored, handler);
      return;
    }

    // Delegate to the shared [TokenRefresher] — single source of truth
    // for `/auth/refresh` so concurrent callers (REST 401 + WS pre-
    // connect / UNAUTHORIZED) coalesce onto one network round-trip and
    // one storage write. The refresher owns terminal-failure handling
    // (clearTokens + onForceLogout); we just retry on success or
    // propagate on null.
    final refreshed = await _tokenRefresher.refresh();
    if (refreshed == null) {
      debugPrint('[Auth] refresh failed — propagating 401 for $path');
      handler.next(err);
      return;
    }
    debugPrint('[Auth] refresh succeeded — retrying $path');
    await _retryWithToken(err.requestOptions, refreshed, handler);
  }

  /// Pulls `error.code` out of the standard `{ success, error: { code, ... } }`
  /// envelope. Returns null when the body is malformed or absent.
  String? _extractErrorCode(Response? response) {
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is Map<String, dynamic>) {
        final code = err['code'];
        if (code is String && code.isNotEmpty) return code;
      }
    }
    return null;
  }

  Future<void> _retryWithToken(
    RequestOptions original,
    String token,
    ErrorInterceptorHandler handler,
  ) async {
    original.headers['Authorization'] = 'Bearer $token';
    try {
      final retryResponse = await _dio.fetch(original);
      handler.resolve(retryResponse);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }
}
