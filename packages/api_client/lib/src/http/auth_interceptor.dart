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
    void Function(AuthForceLogoutEvent event)? onForceLogout,
  })  : _tokenStorage = tokenStorage,
        _dio = dio,
        _tokenRefresher = tokenRefresher,
        _onForceLogout = onForceLogout;

  final TokenStorage _tokenStorage;
  final Dio _dio;
  final TokenRefresher _tokenRefresher;
  final void Function(AuthForceLogoutEvent event)? _onForceLogout;

  static const _requestSessionExtra = 'myshop.auth.request_session';
  static const _boundRetryExtra = 'myshop.auth.bound_retry';

  /// Public request-extra key used to bind a user-initiated operation (most
  /// importantly `/auth/logout`) to the exact SID that owned the tap.
  static const expectedSessionIdentityExtra =
      'myshop.auth.expected_session_identity';
  static const explicitLogoutSessionExtra =
      'myshop.auth.explicit_logout_session';

  /// Paths that do not require an Authorization header. These mirror the
  /// `@Public()` decorator on the backend controllers — keep in sync.
  /// Anything missing here causes the registration / pre-login flows to
  /// fail with a spurious "session is over" local rejection.
  static const _publicPaths = {
    '/auth/register',
    '/auth/check-phone',
    '/auth/login/client',
    '/auth/login/driver',
    '/auth/login/artisan',
    '/auth/verify-otp',
    // OTP channel discovery and resend both happen before verification, so
    // there is no bearer token yet. The prefix covers /channels and /resend.
    '/auth/otp/',
    // Provider post-OTP login flow (v1.2.0) — all pre-auth, no token. The
    // trailing slash prefix covers /auth/provider/login, /verify-otp and
    // /select-role. Without this the interceptor rejects them locally with a
    // spurious "session is over" before they ever hit the wire.
    '/auth/provider/',
    '/auth/refresh',
    '/auth/request-session-recovery',
    // Registration must load the exact current legal documents before a
    // user has an account or access token. The document viewer routes are
    // public too, while /legal/consent and /legal/consent/status remain
    // authenticated and therefore must not be covered by a broad /legal/
    // prefix.
    '/legal/required',
    '/legal/terms',
    '/legal/privacy',
    '/legal/acceptable-use',
    '/legal/community-guidelines',
    '/legal/third-party-licenses',
    '/legal/cookie-policy',
    '/health/ready',
    '/config/',
    '/surge/current',
    // Categories are read during artisan registration (category picker)
    // before the user has authenticated. Marked @Public() on the backend
    // — keep this list aligned.
    '/categories',
    // Ride categories are read during DRIVER registration (tier picker) and
    // the client booking sheet — both before/without auth. Marked @Public()
    // on the backend. NB: this does NOT overlap '/categories' above —
    // '/ride-categories'.contains('/categories') is false (preceding char is
    // '-', not '/'), so it needs its own entry.
    '/ride-categories',
    // Regions are read during PROVIDER registration (home-region picker)
    // before the user has authenticated. Marked @Public() on the backend
    // (GET /v1/regions) — keep this list aligned. Without this entry the
    // interceptor rejects the pre-auth fetch locally and the region step
    // shows "Couldn't load regions" instead of degrading gracefully.
    '/regions',
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

    final explicitLogout =
        options.extra[explicitLogoutSessionExtra] as AuthTokenSnapshot?;
    if (explicitLogout != null && options.path.contains('/auth/logout')) {
      final identity = explicitLogout.identity;
      final token = explicitLogout.accessToken;
      final expectedIdentity =
          options.extra[expectedSessionIdentityExtra] as AuthSessionIdentity?;
      if (identity != null &&
          token != null &&
          (expectedIdentity == null || expectedIdentity == identity)) {
        // Explicit logout fenced this owner out of ordinary storage reads
        // before network I/O. This captured bearer is the sole capability
        // allowed across that fence, and only for the logout endpoint.
        options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
        return;
      }
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'STALE_AUTH_SESSION',
          message: 'Explicit logout lost its exact credential owner.',
        ),
      );
      return;
    }

    // A retry is permanently bound to the exact raw credential state that
    // owned the original request. Recheck at the interceptor's actual
    // dispatch boundary: another account or refresh may have landed after
    // `_retryWithToken` performed its earlier preflight.
    if (options.extra[_boundRetryExtra] == true) {
      final bound = options.extra[_requestSessionExtra];
      if (bound is AuthTokenSnapshot &&
          bound.accessToken != null &&
          bound.identity != null) {
        try {
          final current = await _tokenStorage.readTokenSnapshot();
          if (current.isExactCredentialState(bound)) {
            options.headers['Authorization'] = 'Bearer ${bound.accessToken}';
            handler.next(options);
            return;
          }
        } catch (_) {
          // Fall through to the closed rejection below.
        }
      }
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'STALE_AUTH_SESSION',
          message: 'Bound authentication retry lost its credential owner.',
        ),
      );
      return;
    }

    final expectedIdentity =
        options.extra[expectedSessionIdentityExtra] as AuthSessionIdentity?;
    AuthTokenSnapshot snapshot;
    try {
      snapshot = await _tokenStorage.readTokenSnapshot();
    } catch (error) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'AUTH_STORAGE_UNAVAILABLE',
          message: 'Stored authentication could not be read safely.',
        ),
      );
      return;
    }

    var token = snapshot.accessToken;
    if (token == null && snapshot.refreshToken != null) {
      // Older app versions could leave a refresh-only credential behind.
      // When it has a full session identity this is recoverable rather than
      // proof that the user signed out. Rebuild the access credential through
      // the same shared refresher used by REST and sockets.
      debugPrint(
        '[Auth] access token missing but refresh credential is present — '
        'recovering before ${options.path}',
      );
      token = await _tokenRefresher.refresh(expectedSession: snapshot);
      if (token != null) {
        snapshot = await _tokenStorage.readTokenSnapshot();
      }
    }
    if (expectedIdentity != null && !snapshot.belongsTo(expectedIdentity)) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'STALE_AUTH_SESSION',
          message: 'The session that owned this request was replaced.',
        ),
      );
      return;
    }
    if (token == null) {
      // No recoverable token + non-public path = the user is signed out (or
      // never signed in). Reject locally so background loops that race with
      // logout cannot create a continuous 401/refresh storm.
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
    final tokenIdentity = AuthSessionIdentity.tryParseJwt(token);
    if (tokenIdentity == null ||
        snapshot.identity != tokenIdentity ||
        snapshot.accessToken != token) {
      // Unknown/legacy JWTs cannot participate in session-bound mutation.
      // Preserve storage so bootstrap can show saved-session recovery, but do
      // not send an unauditable credential on a protected request.
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'AUTH_SESSION_IDENTITY_UNAVAILABLE',
          message: 'Stored authentication has no exact session identity.',
        ),
      );
      return;
    }
    options.extra[_requestSessionExtra] = snapshot;
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

    // A request gets at most one session-bound retry. If that exact token also
    // fails, surface the server result without refreshing or mutating whatever
    // session may now be stored.
    if (err.requestOptions.extra[_boundRetryExtra] == true) {
      handler.next(err);
      return;
    }

    final requestSession =
        err.requestOptions.extra[_requestSessionExtra] as AuthTokenSnapshot?;
    final requestIdentity = requestSession?.identity;
    if (requestSession == null || requestIdentity == null) {
      debugPrint('[Auth] 401 has no exact request session — failing closed');
      handler.next(err);
      return;
    }

    AuthTokenSnapshot current;
    try {
      current = await _tokenStorage.readTokenSnapshot();
    } catch (error) {
      debugPrint('[Auth] cannot verify 401 session owner: $error');
      handler.next(err);
      return;
    }
    if (!current.belongsTo(requestIdentity)) {
      debugPrint(
        '[Auth] stale 401 belongs to a replaced session — rejecting $path',
      );
      _rejectStaleRetry(err.requestOptions, handler);
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
      final cleared = await _tokenStorage
          .clearAuthTokensOnlyForIdentityIfCurrent(requestIdentity);
      if (cleared) {
        _onForceLogout?.call(AuthForceLogoutEvent.fromSnapshot(requestSession));
      }
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
      final fresh = await _tokenStorage.readTokenSnapshot();
      final freshToken = fresh.accessToken;
      if (freshToken != null &&
          fresh.belongsTo(requestIdentity) &&
          freshToken != requestSession.accessToken) {
        debugPrint('[Auth] retrying $path with refreshed token');
        await _retryWithToken(err.requestOptions, fresh, handler);
        return;
      }
      if (fresh.hasCredentials && !fresh.belongsTo(requestIdentity)) {
        _rejectStaleRetry(err.requestOptions, handler);
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
    if (current.accessToken != null &&
        current.accessToken != requestSession.accessToken) {
      debugPrint('[Auth] another request already refreshed — retrying $path');
      await _retryWithToken(err.requestOptions, current, handler);
      return;
    }

    // Delegate to the shared [TokenRefresher] — single source of truth
    // for `/auth/refresh` so concurrent callers (REST 401 + WS pre-
    // connect / UNAUTHORIZED) coalesce onto one network round-trip and
    // one storage write. The refresher owns terminal-failure handling
    // (clearTokens + onForceLogout); we just retry on success or
    // propagate on null.
    final refreshed =
        await _tokenRefresher.refresh(expectedSession: requestSession);
    if (refreshed == null) {
      try {
        final afterRefresh = await _tokenStorage.readTokenSnapshot();
        if (afterRefresh.hasCredentials &&
            !afterRefresh.belongsTo(requestIdentity)) {
          _rejectStaleRetry(err.requestOptions, handler);
          return;
        }
      } catch (_) {
        _rejectStaleRetry(err.requestOptions, handler);
        return;
      }
      debugPrint('[Auth] refresh failed — propagating 401 for $path');
      handler.next(err);
      return;
    }
    final refreshedSession = await _tokenStorage.readTokenSnapshot();
    if (!refreshedSession.belongsTo(requestIdentity) ||
        refreshedSession.accessToken != refreshed) {
      debugPrint(
        '[Auth] refreshed token was replaced before retry — propagating $path',
      );
      if (refreshedSession.hasCredentials &&
          !refreshedSession.belongsTo(requestIdentity)) {
        _rejectStaleRetry(err.requestOptions, handler);
      } else {
        handler.next(err);
      }
      return;
    }
    debugPrint('[Auth] refresh succeeded — retrying $path');
    await _retryWithToken(err.requestOptions, refreshedSession, handler);
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
    AuthTokenSnapshot session,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final beforeDispatch = await _tokenStorage.readTokenSnapshot();
      if (!beforeDispatch.isExactCredentialState(session)) {
        _rejectStaleRetry(original, handler);
        return;
      }
    } catch (_) {
      _rejectStaleRetry(original, handler);
      return;
    }

    original.extra[_requestSessionExtra] = session;
    original.extra[_boundRetryExtra] = true;
    original.headers['Authorization'] = 'Bearer ${session.accessToken}';
    try {
      final retryResponse = await _dio.fetch(original);
      final afterResponse = await _tokenStorage.readTokenSnapshot();
      if (!afterResponse.isExactCredentialState(session)) {
        _rejectStaleRetry(original, handler);
        return;
      }
      handler.resolve(retryResponse);
    } on DioException catch (retryErr) {
      try {
        final afterError = await _tokenStorage.readTokenSnapshot();
        if (!afterError.isExactCredentialState(session)) {
          _rejectStaleRetry(original, handler);
          return;
        }
      } catch (_) {
        _rejectStaleRetry(original, handler);
        return;
      }
      handler.next(retryErr);
    } catch (_) {
      _rejectStaleRetry(original, handler);
    }
  }

  void _rejectStaleRetry(
    RequestOptions request,
    ErrorInterceptorHandler handler,
  ) {
    handler.reject(
      DioException(
        requestOptions: request,
        type: DioExceptionType.cancel,
        error: 'STALE_AUTH_SESSION',
        message: 'The authenticated session changed during request retry.',
      ),
    );
  }
}
