import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_dtos.dart';
import '../models/auth_error_mapper.dart';
import 'token_storage.dart';

/// Process-wide single-flight for `/auth/refresh`.
///
/// Both the REST [AuthInterceptor] (on 401) and the [SocketService]
/// (proactively before connect, reactively on UNAUTHORIZED) need to swap
/// the access token for a fresh pair. Before this class existed each
/// kept its own `_inFlightRefresh` Future, and the two paths could race
/// the same refresh token through the backend. With refresh-token
/// rotation the loser of the race gets `REFRESH_TOKEN_REUSED` —
/// canonical signal for token replay — and the app force-logs the user
/// out mid-session.
///
/// All refresh callers now go through this class. The single shared
/// `_inFlight` future guarantees that concurrent calls coalesce onto
/// one network round-trip and one storage write, regardless of which
/// layer fired first.
///
/// Failure handling preserves existing semantics:
///   - `REFRESH_TOKEN_REUSED` / `INVALID_TOKEN` / `TOKEN_EXPIRED` →
///     full `clearTokens()` + `onForceLogout` (sign-in fresh).
///   - Other 4xx on `/auth/refresh` → soft clear of just the JWT pair
///     + `onForceLogout` (preserves cached identity for one-tap
///     re-login).
///   - Non-4xx (network error, timeout) → return null without
///     clearing — caller decides whether to retry.
class TokenRefresher {
  TokenRefresher({
    required Dio dio,
    required TokenStorage tokenStorage,
    void Function()? onForceLogout,
  })  : _dio = dio,
        _tokenStorage = tokenStorage,
        _onForceLogout = onForceLogout;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final void Function()? _onForceLogout;

  Future<String?>? _inFlight;

  /// Runs `/auth/refresh` if no other caller is already running it,
  /// otherwise awaits the in-flight one. Returns the new access token,
  /// or null on terminal failure (which also fires `onForceLogout`).
  Future<String?> refresh() {
    return _inFlight ??= () async {
      try {
        final refreshToken = await _tokenStorage.readRefreshToken();
        if (refreshToken == null) {
          debugPrint('[TokenRefresher] no refresh token — forcing logout');
          _onForceLogout?.call();
          return null;
        }

        debugPrint('[TokenRefresher] POST /auth/refresh →');
        final response = await _dio.post(
          '/auth/refresh',
          data: RefreshRequest(refreshToken: refreshToken).toJson(),
        );
        debugPrint('[TokenRefresher] POST /auth/refresh ← '
            '${response.statusCode}');

        final body = response.data;
        if (body is! Map<String, dynamic>) {
          debugPrint('[TokenRefresher] body not a map: $body');
          return null;
        }
        final payload = (body['data'] is Map<String, dynamic>
            ? body['data']
            : body) as Map<String, dynamic>;

        final newAccessToken = payload['accessToken'] as String?;
        if (newAccessToken == null) {
          debugPrint(
            '[TokenRefresher] response missing accessToken: $payload',
          );
          return null;
        }

        // Rotation: when the response includes a new refreshToken we
        // MUST persist it. Otherwise the next refresh would reuse the
        // already-consumed token and the backend would reject with
        // REFRESH_TOKEN_REUSED → forced logout.
        final newRefreshToken = payload['refreshToken'] as String?;
        if (newRefreshToken != null && newRefreshToken != refreshToken) {
          await _tokenStorage.writeTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );
        } else {
          await _tokenStorage.writeAccessToken(newAccessToken);
        }
        debugPrint('[TokenRefresher] new tokens persisted');
        return newAccessToken;
      } on DioException catch (e) {
        return _handleRefreshError(e);
      } catch (e, st) {
        debugPrint('[TokenRefresher] unexpected: $e\n$st');
        return null;
      } finally {
        _inFlight = null;
      }
    }();
  }

  Future<String?> _handleRefreshError(DioException e) async {
    final status = e.response?.statusCode;
    final code = _extractErrorCode(e.response);
    debugPrint(
      '[TokenRefresher] DioException: status=$status code=$code '
      'body=${e.response?.data}',
    );

    const terminalCodes = {
      AuthErrorCodes.tokenExpired,
      AuthErrorCodes.invalidToken,
      AuthErrorCodes.refreshTokenReused,
    };
    if (status == 401) {
      if (code != null && terminalCodes.contains(code)) {
        debugPrint(
          '[TokenRefresher] terminal failure ($code) — clearing tokens',
        );
        await _tokenStorage.clearTokens();
        _onForceLogout?.call();
      } else {
        debugPrint(
          '[TokenRefresher] 401 (code="$code") — soft logout',
        );
        await _tokenStorage.clearAuthTokensOnly();
        _onForceLogout?.call();
      }
    } else if (status != null && status >= 400 && status < 500) {
      debugPrint(
        '[TokenRefresher] non-401 4xx ($status, code="$code") — '
        'NOT clearing tokens (treating as transient client error)',
      );
    }
    return null;
  }

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
}
