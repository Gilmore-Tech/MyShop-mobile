import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_dtos.dart';
import '../models/auth_error_mapper.dart';
import 'token_storage.dart';

/// Interceptor that:
/// 1. Injects the Bearer token on every authenticated request.
/// 2. Handles 401 responses by refreshing the token and retrying — with
///    a dedup that prevents redundant refreshes when multiple concurrent
///    requests 401 against the same stale token.
/// 3. Emits a logout signal when the refresh token itself is dead.
///
/// Uses [QueuedInterceptor] so that concurrent 401s serialize through
/// [onError]. The dedup check inside still matters: when backend rotates
/// refresh tokens (rollout in progress — see backend B4), a second call
/// to `/auth/refresh` with an already-consumed refresh token would force
/// logout even though the first refresh succeeded.
///
/// Note: we deliberately do NOT pre-refresh expired tokens inside
/// [onRequest]. Posting to `/auth/refresh` from within an interceptor
/// handler deadlocks `QueuedInterceptor` (the refresh request's own
/// handlers get queued behind the outer handler awaiting them). The
/// socket layer does proactive pre-refresh from outside the interceptor
/// chain; the REST path relies on the 401 → refresh round-trip.
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

  /// Single-flight guard so a burst of requests racing with an expired
  /// token don't each post `/auth/refresh`.
  Future<String?>? _inFlightRefresh;

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
    if (_isPublic(options.path)) {
      handler.next(options);
      return;
    }

    final token = await _tokenStorage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
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
    final attachedToken = attachedAuth != null && attachedAuth.startsWith('Bearer ')
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
        final payload =
            (body['data'] is Map<String, dynamic> ? body['data'] : body)
                as Map<String, dynamic>;

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
            debugPrint('[Auth] terminal refresh failure ($code) — clearing tokens');
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
