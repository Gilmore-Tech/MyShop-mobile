import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_dtos.dart';
import '../models/auth_error_mapper.dart';
import 'refresh_attempt_store.dart';
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
/// All refresh callers now go through this class. Calls for the same exact raw
/// credential state coalesce onto one network round-trip and one storage
/// write. A newer login or a bootstrap proof transition uses a different
/// flight and can never inherit an older session's result.
///
/// Failure handling is deliberately allow-listed:
///   - Explicit terminal credential/account codes full-clear only the exact
///     current owner and dispatch `onForceLogout`.
///   - `SESSION_TAKEN_OVER` clears auth tokens for that SID across rotations
///     while retaining cached profile metadata.
///   - Refresh contention, unclassified/non-terminal 4xx responses, network
///     errors, and timeouts preserve the local session for recovery/retry.
class TokenRefresher {
  TokenRefresher({
    required Dio dio,
    required TokenStorage tokenStorage,
    RefreshAttemptStore? refreshAttemptStore,
    void Function(AuthForceLogoutEvent event)? onForceLogout,
    Future<void> Function(Duration duration)? delay,
  })  : _dio = dio,
        _tokenStorage = tokenStorage,
        _refreshAttemptStore = refreshAttemptStore ??
            (tokenStorage is RefreshAttemptStore
                ? tokenStorage as RefreshAttemptStore
                : VolatileRefreshAttemptStore()),
        _onForceLogout = onForceLogout,
        _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final RefreshAttemptStore _refreshAttemptStore;
  final void Function(AuthForceLogoutEvent event)? _onForceLogout;
  final Future<void> Function(Duration duration) _delay;

  final Map<({String? accessToken, String refreshToken}), Future<String?>>
      _inFlightByCredentialState = {};

  /// Refresh the exact credential epoch observed by the caller.
  ///
  /// Concurrent callers using the same rotating refresh token share one
  /// request. A caller from a newer login never joins an older session's
  /// future, even when both calls overlap in one process.
  Future<String?> refresh({AuthTokenSnapshot? expectedSession}) =>
      _refresh(expectedSession: expectedSession, allowLegacyUpgrade: false);

  /// Bootstrap-only bridge for tokens minted before session IDs were added.
  ///
  /// Ordinary requests never use this path. Storage accepts the result only
  /// when the exact raw legacy credentials are still current. A complete
  /// pre-SID pair must return one full identity for the same principal. The
  /// released split-upgrade state additionally sends its signed SID-bearing
  /// access token as proof and requires the returned pair to keep that SID.
  Future<String?> refreshForBootstrap({
    required AuthTokenSnapshot expectedSession,
  }) =>
      _refresh(expectedSession: expectedSession, allowLegacyUpgrade: true);

  /// Repair a fenced explicit-logout owner only far enough to revoke its
  /// exact server SID.
  ///
  /// The successor is persisted behind the durable fence and is therefore
  /// invisible to ordinary REST, WebSocket, bootstrap, and refresh callers.
  /// This privileged path never republishes an authenticated local session.
  Future<AuthTokenSnapshot?> refreshForExplicitLogout({
    required AuthExplicitLogoutFence fence,
  }) async {
    final owner = await _tokenStorage.readExplicitLogoutOwner(fence);
    final refreshToken = owner?.refreshToken;
    if (owner == null || refreshToken == null) return null;
    if (owner.identity == null &&
        !owner.isPreSessionIdCredentialState &&
        !owner.isInterruptedPreSessionIdUpgrade &&
        !owner.isSessionRoleAccountIdUpgrade) {
      return null;
    }

    late final String refreshAttemptId;
    try {
      refreshAttemptId = await _refreshAttemptStore.readOrCreate(refreshToken);
    } catch (error) {
      debugPrint(
        '[TokenRefresher] explicit-logout attempt persistence failed: $error',
      );
      return null;
    }

    for (var attempt = 1; attempt <= 3; attempt += 1) {
      final current = await _tokenStorage.readExplicitLogoutOwner(fence);
      if (current == null || !current.hasExactRawCredentials(owner)) {
        return null;
      }
      try {
        final response = await _dio.post(
          '/auth/refresh',
          data: RefreshRequest(
            refreshToken: refreshToken,
            accessToken:
                owner.isPreSessionIdCredentialState ? null : owner.accessToken,
            refreshAttemptId: refreshAttemptId,
          ).toJson(),
        );
        final body = response.data;
        if (body is! Map<String, dynamic>) return null;
        final payload = (body['data'] is Map<String, dynamic>
            ? body['data']
            : body) as Map<String, dynamic>;
        final accessToken = payload['accessToken'] as String?;
        if (accessToken == null || accessToken.isEmpty) return null;
        final successorRefresh =
            (payload['refreshToken'] as String?) ?? refreshToken;
        final persisted =
            await _tokenStorage.replaceExplicitLogoutTokensIfCurrent(
          fence: fence,
          expected: owner,
          accessToken: accessToken,
          refreshToken: successorRefresh,
        );
        if (!persisted) return null;
        final successor = await _tokenStorage.readExplicitLogoutOwner(fence);
        if (successor?.accessToken != accessToken ||
            successor?.refreshToken != successorRefresh ||
            successor?.identity == null) {
          return null;
        }
        try {
          await _refreshAttemptStore.clearIfMatches(
            refreshToken: refreshToken,
            attemptId: refreshAttemptId,
          );
        } catch (error) {
          debugPrint(
            '[TokenRefresher] explicit-logout attempt cleanup deferred: '
            '$error',
          );
        }
        return successor;
      } on DioException catch (error) {
        final code = _extractErrorCode(error.response);
        if (code == AuthErrorCodes.refreshInFlight && attempt < 3) {
          await _delay(Duration(milliseconds: 250 * attempt));
          continue;
        }
        // Explicit logout remains locally final for every network/server
        // outcome. The repository finishes the fence after this best-effort
        // repair returns.
        return null;
      } catch (error) {
        debugPrint(
          '[TokenRefresher] explicit-logout repair failed: $error',
        );
        return null;
      }
    }
    return null;
  }

  Future<String?> _refresh({
    AuthTokenSnapshot? expectedSession,
    required bool allowLegacyUpgrade,
  }) async {
    AuthTokenSnapshot owner;
    try {
      owner = expectedSession ?? await _tokenStorage.readTokenSnapshot();
    } catch (error) {
      debugPrint('[TokenRefresher] token snapshot unavailable: $error');
      return null;
    }

    final refreshToken = owner.refreshToken;
    if (refreshToken == null) {
      debugPrint('[TokenRefresher] no refresh token');
      if (owner.identity != null && owner.hasCredentials) {
        final cleared = await _tokenStorage.clearTokensIfCurrent(owner);
        if (cleared) {
          _onForceLogout?.call(AuthForceLogoutEvent.fromSnapshot(owner));
        }
      }
      return null;
    }
    final legacyUpgrade = owner.isPreSessionIdCredentialState;
    final interruptedLegacyUpgrade = owner.isInterruptedPreSessionIdUpgrade;
    final sessionLineageUpgrade = owner.isSessionRoleAccountIdUpgrade;
    if (owner.identity == null &&
        (!allowLegacyUpgrade ||
            (!legacyUpgrade &&
                !interruptedLegacyUpgrade &&
                !sessionLineageUpgrade))) {
      // Tokens without an exact sub/role/sid tuple cannot safely own a
      // normal refresh mutation. Preserve them for saved-session recovery
      // instead of guessing which account should be cleared or updated.
      debugPrint(
        '[TokenRefresher] refresh token has unknown/mixed session identity',
      );
      return null;
    }

    final flightKey = (
      accessToken: owner.accessToken,
      refreshToken: refreshToken,
    );
    final existing = _inFlightByCredentialState[flightKey];
    if (existing != null) return existing;

    late final Future<String?> flight;
    flight = _refreshOwned(
      owner,
      legacyUpgrade: legacyUpgrade,
      interruptedLegacyUpgrade: interruptedLegacyUpgrade,
      sessionLineageUpgrade: sessionLineageUpgrade,
    );
    _inFlightByCredentialState[flightKey] = flight;
    try {
      return await flight;
    } finally {
      if (identical(_inFlightByCredentialState[flightKey], flight)) {
        _inFlightByCredentialState.remove(flightKey);
      }
    }
  }

  Future<String?> _refreshOwned(
    AuthTokenSnapshot owner, {
    required bool legacyUpgrade,
    required bool interruptedLegacyUpgrade,
    required bool sessionLineageUpgrade,
  }) async {
    late final String refreshAttemptId;
    try {
      final beforeAttempt = await _tokenStorage.readTokenSnapshot();
      if (!beforeAttempt.hasExactRawCredentials(owner)) {
        return _currentAccessAfterOwnerChange(
          beforeAttempt,
          owner,
          legacyUpgrade: legacyUpgrade,
          interruptedLegacyUpgrade: interruptedLegacyUpgrade,
          sessionLineageUpgrade: sessionLineageUpgrade,
        );
      }
      final attemptStore = _refreshAttemptStore;
      final created = attemptStore is SessionBoundRefreshAttemptStore
          ? await attemptStore.readOrCreateIfCurrent(owner)
          : await attemptStore.readOrCreate(owner.refreshToken!);
      if (created == null) return null;
      refreshAttemptId = created;
      final afterAttempt = await _tokenStorage.readTokenSnapshot();
      if (!afterAttempt.hasExactRawCredentials(owner)) {
        return _currentAccessAfterOwnerChange(
          afterAttempt,
          owner,
          legacyUpgrade: legacyUpgrade,
          interruptedLegacyUpgrade: interruptedLegacyUpgrade,
          sessionLineageUpgrade: sessionLineageUpgrade,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[TokenRefresher] refresh-attempt persistence failed: '
        '$error\n$stackTrace',
      );
      return null;
    }

    try {
      for (var attempt = 1; attempt <= 3; attempt += 1) {
        final current = await _tokenStorage.readTokenSnapshot();
        if (!current.hasExactRawCredentials(owner)) {
          if (legacyUpgrade) return null;
          if (interruptedLegacyUpgrade || sessionLineageUpgrade) {
            return _currentAccessForSameUpgradeGeneration(current, owner);
          }
          return _currentAccessForSameSession(current, owner.identity!);
        }

        try {
          debugPrint('[TokenRefresher] POST /auth/refresh →');
          final response = await _dio.post(
            '/auth/refresh',
            data: RefreshRequest(
              refreshToken: owner.refreshToken!,
              // A coherent pair minted before SIDs existed must omit access
              // proof: the backend's proof path intentionally accepts only a
              // signed SID-bearing access token. Interrupted legacy upgrades
              // and modern rotations do send that proof so response-loss
              // recovery can bind the predecessor to its exact SID.
              accessToken: legacyUpgrade ? null : owner.accessToken,
              refreshAttemptId: refreshAttemptId,
            ).toJson(),
          );
          debugPrint(
            '[TokenRefresher] POST /auth/refresh ← ${response.statusCode}',
          );

          final body = response.data;
          if (body is! Map<String, dynamic>) {
            debugPrint('[TokenRefresher] body not a map: $body');
            return null;
          }
          final payload = (body['data'] is Map<String, dynamic>
              ? body['data']
              : body) as Map<String, dynamic>;

          final newAccessToken = payload['accessToken'] as String?;
          if (newAccessToken == null || newAccessToken.isEmpty) {
            debugPrint('[TokenRefresher] response missing accessToken');
            return null;
          }
          final newRefreshToken =
              (payload['refreshToken'] as String?) ?? owner.refreshToken!;

          final persisted = sessionLineageUpgrade
              ? await _tokenStorage.replaceSessionLineageTokensIfCurrent(
                  expected: owner,
                  accessToken: newAccessToken,
                  refreshToken: newRefreshToken,
                )
              : interruptedLegacyUpgrade
                  ? await _tokenStorage.replaceInterruptedLegacyTokensIfCurrent(
                      expected: owner,
                      accessToken: newAccessToken,
                      refreshToken: newRefreshToken,
                    )
                  : legacyUpgrade
                      ? await _tokenStorage.replaceLegacyTokensIfCurrent(
                          expected: owner,
                          accessToken: newAccessToken,
                          refreshToken: newRefreshToken,
                        )
                      : await _tokenStorage.replaceTokensIfCurrent(
                          expected: owner,
                          accessToken: newAccessToken,
                          refreshToken: newRefreshToken,
                        );
          final afterWrite = await _tokenStorage.readTokenSnapshot();
          if (!persisted) {
            debugPrint(
              '[TokenRefresher] stale refresh result discarded; '
              'credentials changed while the request was in flight',
            );
            if (legacyUpgrade) return null;
            if (interruptedLegacyUpgrade || sessionLineageUpgrade) {
              return _currentAccessForSameUpgradeGeneration(afterWrite, owner);
            }
            return _currentAccessForSameSession(afterWrite, owner.identity!);
          }
          final validAfterWrite =
              interruptedLegacyUpgrade || sessionLineageUpgrade
                  ? _belongsToUpgradeGeneration(afterWrite, owner) &&
                      afterWrite.accessToken == newAccessToken &&
                      afterWrite.refreshToken == newRefreshToken
                  : legacyUpgrade
                      ? afterWrite.identity != null &&
                          afterWrite.identity!.principal == owner.principal &&
                          afterWrite.accessToken == newAccessToken &&
                          afterWrite.refreshToken == newRefreshToken
                      : afterWrite.belongsTo(owner.identity!) &&
                          afterWrite.accessToken == newAccessToken;
          if (!validAfterWrite) {
            debugPrint(
              '[TokenRefresher] refreshed credentials were replaced before '
              'the caller resumed',
            );
            return null;
          }
          try {
            await _refreshAttemptStore.clearIfMatches(
              refreshToken: owner.refreshToken!,
              attemptId: refreshAttemptId,
            );
          } catch (error) {
            // The successor pair is already canonical. A stale record is
            // harmless and is replaced when its token digest changes.
            debugPrint(
              '[TokenRefresher] refresh-attempt cleanup deferred: $error',
            );
          }
          debugPrint('[TokenRefresher] new token pair persisted');
          return newAccessToken;
        } on DioException catch (error) {
          final code = _extractErrorCode(error.response);
          if (code == AuthErrorCodes.refreshInFlight && attempt < 3) {
            final backoff = Duration(milliseconds: 250 * attempt);
            debugPrint(
              '[TokenRefresher] refresh contention — retrying in '
              '${backoff.inMilliseconds}ms',
            );
            await _delay(backoff);
            continue;
          }
          return _handleRefreshError(error, owner);
        }
      }
      return null;
    } catch (error, stackTrace) {
      debugPrint('[TokenRefresher] unexpected: $error\n$stackTrace');
      return null;
    }
  }

  String? _currentAccessAfterOwnerChange(
    AuthTokenSnapshot current,
    AuthTokenSnapshot owner, {
    required bool legacyUpgrade,
    required bool interruptedLegacyUpgrade,
    required bool sessionLineageUpgrade,
  }) {
    if (legacyUpgrade) return null;
    if (interruptedLegacyUpgrade || sessionLineageUpgrade) {
      return _currentAccessForSameUpgradeGeneration(current, owner);
    }
    final identity = owner.identity;
    return identity == null
        ? null
        : _currentAccessForSameSession(current, identity);
  }

  String? _currentAccessForSameSession(
    AuthTokenSnapshot current,
    AuthSessionIdentity expected,
  ) {
    if (!current.belongsTo(expected)) return null;
    return current.accessToken;
  }

  String? _currentAccessForSameUpgradeGeneration(
    AuthTokenSnapshot current,
    AuthTokenSnapshot owner,
  ) {
    if (!_belongsToUpgradeGeneration(current, owner)) return null;
    return current.accessToken;
  }

  bool _belongsToUpgradeGeneration(
    AuthTokenSnapshot current,
    AuthTokenSnapshot owner,
  ) {
    final expectedGeneration = owner.isInterruptedPreSessionIdUpgrade
        ? owner.accessLineage?.generation
        : owner.generation;
    final currentIdentity = current.identity;
    if (expectedGeneration == null ||
        currentIdentity == null ||
        currentIdentity.generation != expectedGeneration) {
      return false;
    }
    final carriedRoleAccountId = owner.carriedRoleAccountId;
    return carriedRoleAccountId == null ||
        currentIdentity.roleAccountId == carriedRoleAccountId;
  }

  Future<String?> _handleRefreshError(
    DioException e,
    AuthTokenSnapshot owner,
  ) async {
    final status = e.response?.statusCode;
    final code = _extractErrorCode(e.response);
    debugPrint(
      '[TokenRefresher] DioException: status=$status code=$code',
    );

    const terminalCodes = {
      AuthErrorCodes.tokenExpired,
      AuthErrorCodes.invalidToken,
      AuthErrorCodes.refreshTokenReused,
      AuthErrorCodes.userNotFound,
      AuthErrorCodes.roleAccountUnavailable,
      AuthErrorCodes.roleAccountMismatch,
    };
    if (code == AuthErrorCodes.refreshInFlight) {
      debugPrint(
        '[TokenRefresher] refresh contention remained after retries — '
        'keeping the local session',
      );
      return null;
    }
    final invalidLegacyProof =
        code == AuthErrorCodes.legacyBootstrapProofInvalid &&
            (owner.isPreSessionIdCredentialState ||
                owner.isInterruptedPreSessionIdUpgrade);
    if ((code != null && terminalCodes.contains(code)) || invalidLegacyProof) {
      debugPrint(
        '[TokenRefresher] terminal failure ($code) — conditionally '
        'clearing tokens',
      );
      final cleared = await _tokenStorage.clearTokensIfCurrent(owner);
      if (cleared) {
        _onForceLogout?.call(AuthForceLogoutEvent.fromSnapshot(owner));
      } else {
        debugPrint(
          '[TokenRefresher] stale terminal response ignored; a newer '
          'credential epoch is active',
        );
      }
    } else if (code == AuthErrorCodes.sessionTakenOver) {
      debugPrint(
        '[TokenRefresher] session takeover — conditionally clearing only '
        'the fenced JWT pair',
      );
      final ownerIdentity = owner.identity;
      final cleared = ownerIdentity != null
          ? await _tokenStorage
              .clearAuthTokensOnlyForIdentityIfCurrent(ownerIdentity)
          : await _tokenStorage.clearAuthTokensOnlyIfCurrent(owner);
      if (cleared) {
        _onForceLogout?.call(AuthForceLogoutEvent.fromSnapshot(owner));
      }
    } else if (status == 401) {
      // A proxy, gateway, or truncated edge response can preserve the HTTP
      // status while dropping the backend's structured error code. Status
      // alone is not proof that the rotating credential is dead.
      debugPrint(
        '[TokenRefresher] unclassified 401 (code="$code") — preserving '
        'the local session for retry/recovery',
      );
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
