import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_dtos.dart';
import '../models/auth_error_mapper.dart';
import 'token_storage.dart';

/// Interceptor that:
/// 1. Injects the Bearer token on every authenticated request.
/// 2. Handles 401 responses by refreshing the token and retrying — with
///    a single-flight [_inFlightRefresh] so a burst of concurrent 401s
///    against the same stale token only fires one `/auth/refresh`. A
///    second dedup compares the stored token to the one attached when
///    the request went out, so a request that 401s after another caller
///    already rotated the token just retries with the new one instead
///    of triggering another refresh.
/// 3. Emits a logout signal when the refresh token itself is dead.
///
/// Must extend plain [Interceptor], NOT [QueuedInterceptor]. Dio's
/// `QueuedInterceptor` serializes onError through a single queue per
/// instance; awaiting `_dio.post('/auth/refresh', ...)` from inside an
/// onError handler means the refresh's own onError (when the refresh
/// itself returns 4xx) gets queued behind the outer handler awaiting
/// it — deadlocking the chain and stranding the app on whatever screen
/// the failed request was driving. Concurrency is already handled by
/// [_inFlightRefresh] + the stored-vs-attached dedup, so the queue was
/// redundant insurance with a sharp edge.
///
/// We do not pre-refresh expired tokens in [onRequest]; the socket layer
/// handles proactive refresh from outside the interceptor chain, and
/// the REST path relies on the 401 → refresh round-trip.
class AuthInterceptor extends Interceptor {
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

  /// Single-flight guard so a burst of requests racing with an expired
  /// token don't each post `/auth/refresh`.
  Future<String?>? _inFlightRefresh;

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

    // Actually attempt the refresh.
    final refreshed = await _refreshOnce();
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

  /// POST `/auth/refresh` with single-flight dedup.
  /// On success returns the new access token and writes it to storage.
  /// On hard auth failure clears tokens and fires [_onForceLogout].
  Future<String?> _refreshOnce() {
    return _inFlightRefresh ??= () async {
      try {
        final refreshToken = await _tokenStorage.readRefreshToken();
        if (refreshToken == null) {
          debugPrint('[Auth] no refresh token in storage — forcing logout');
          _onForceLogout?.call();
          return null;
        }

        debugPrint('[Auth] POST /auth/refresh →');
        final response = await _dio.post(
          '/auth/refresh',
          data: RefreshRequest(refreshToken: refreshToken).toJson(),
        );
        debugPrint('[Auth] POST /auth/refresh ← ${response.statusCode}');

        final body = response.data;
        if (body is! Map<String, dynamic>) {
          debugPrint('[Auth] refresh body not a map: $body');
          return null;
        }
        final payload = (body['data'] is Map<String, dynamic>
            ? body['data']
            : body) as Map<String, dynamic>;

        final newAccessToken = payload['accessToken'] as String?;
        if (newAccessToken == null) {
          debugPrint('[Auth] refresh response missing accessToken: $payload');
          return null;
        }
        await _tokenStorage.writeAccessToken(newAccessToken);

        // Rotation support: backend is adding rotation (B4). When it
        // ships, the response will also carry a new refreshToken — we
        // persist it so the next refresh uses the rotated token. Until
        // then this key is absent and we keep the old refresh token.
        final newRefreshToken = payload['refreshToken'] as String?;
        if (newRefreshToken != null && newRefreshToken != refreshToken) {
          await _tokenStorage.writeTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );
        }

        return newAccessToken;
      } on DioException catch (e) {
        debugPrint(
          '[Auth] refresh DioException: status=${e.response?.statusCode} '
          'body=${e.response?.data}',
        );
        // Refresh-failure policy:
        //   - 401 with TOKEN_EXPIRED / INVALID_TOKEN / REFRESH_TOKEN_REUSED →
        //     the entire token chain is dead. Wipe full identity context
        //     so the user signs in fresh and no stale cached profile
        //     flashes on the way to /signin.
        //   - 401 with SESSION_TAKEN_OVER → another device claimed the
        //     session. Soft-clear only the JWT pair, preserving cached
        //     identity for one-tap re-login.
        //   - 401 with anything else (or no code) → still terminal, but
        //     soft-clear: a 401 on /auth/refresh can only mean "this
        //     refresh token is rejected" — there's no recovery path, so
        //     we MUST kick the user out. Backend is migrating to the
        //     specific codes (rollout in progress); until that's
        //     consistent we fall back to soft-clear so the app isn't
        //     stranded with dead tokens.
        //   - other 4xx (400, 403, 422 etc.) → don't clear. These are
        //     client errors, not auth-chain death.
        final status = e.response?.statusCode;
        final code = _extractErrorCode(e.response);
        const terminalCodes = {
          AuthErrorCodes.tokenExpired,
          AuthErrorCodes.invalidToken,
          AuthErrorCodes.refreshTokenReused,
        };
        if (status == 401) {
          if (code != null && terminalCodes.contains(code)) {
            debugPrint(
              '[Auth] terminal refresh failure ($code) — clearing tokens',
            );
            await _tokenStorage.clearTokens();
            _onForceLogout?.call();
          } else {
            debugPrint(
              '[Auth] refresh 401 (code="$code") — soft logout',
            );
            await _tokenStorage.clearAuthTokensOnly();
            _onForceLogout?.call();
          }
        } else if (status != null && status >= 400 && status < 500) {
          debugPrint(
            '[Auth] refresh non-401 4xx ($status, code="$code") — '
            'NOT clearing tokens (likely a client error, not auth death)',
          );
        }
        return null;
      } catch (e, st) {
        debugPrint('[Auth] refresh crashed: $e\n$st');
        return null;
      } finally {
        _inFlightRefresh = null;
      }
    }();
  }
}
