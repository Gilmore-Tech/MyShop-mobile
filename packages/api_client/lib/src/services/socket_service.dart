import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import '../http/token_storage.dart';
import '../models/auth_dtos.dart';

/// Callback for when a Socket.IO event is received.
typedef SocketEventCallback = void Function(dynamic data);

/// Manages the Socket.IO connection to the MyShop backend.
///
/// Handles:
/// - Authenticated connection with Bearer token
/// - Proactive token refresh before connect when the JWT is about to expire
/// - Reactive token refresh + reconnect when the server emits
///   `exception { error: UNAUTHORIZED }`
/// - Automatic reconnection on disconnect
/// - Event subscription/unsubscription
/// - Connection lifecycle (connect/disconnect/dispose)
class SocketService {
  SocketService({
    required ApiConfig config,
    required TokenStorage tokenStorage,
    required Dio dio,
    void Function()? onForceLogout,
  })  : _config = config,
        _tokenStorage = tokenStorage,
        _dio = dio,
        _onForceLogout = onForceLogout;

  final ApiConfig _config;
  final TokenStorage _tokenStorage;
  final Dio _dio;
  final void Function()? _onForceLogout;

  io.Socket? _socket;
  bool _disposed = false;

  // Single-flight guards so a UNAUTHORIZED storm or overlapping connect()
  // calls don't fan out into multiple concurrent refresh + reconnect cycles.
  Future<String?>? _inFlightRefresh;
  Future<void>? _inFlightReconnect;

  final _connectionController = StreamController<bool>.broadcast();

  /// Stream that emits `true` when connected, `false` when disconnected.
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Whether the socket is currently connected.
  bool get isConnected => _socket?.connected ?? false;

  /// Connect to the Socket.IO server with the stored access token.
  Future<void> connect() async {
    if (_disposed) return;
    if (_socket?.connected == true) return;

    var token = await _tokenStorage.readAccessToken();
    if (token == null) {
      debugPrint('[WS] No access token — skipping socket connect');
      return;
    }

    // Proactively refresh if the access token is already expired or will
    // expire within the next 30s. Avoids the round-trip of opening the
    // socket only for the server to immediately reject with UNAUTHORIZED.
    //
    // The backend runs on Render free tier and can take 30–60s to wake from
    // a cold start, so we retry the refresh a few times with backoff before
    // giving up. Once it returns, the socket connects normally.
    if (_isTokenExpiringSoon(token)) {
      debugPrint('[WS] Access token expired/expiring — refreshing pre-connect');
      final refreshed = await _refreshAccessTokenWithRetry();
      if (refreshed == null) {
        debugPrint('[WS] Pre-connect refresh failed — aborting connect');
        return;
      }
      token = refreshed;
    }

    _socket?.dispose();

    // Connect to the /location/track namespace — backend's location gateway
    // auto-joins role-specific rooms (artisan:{userId} or driver:{userId})
    // based on the JWT payload.
    final nsUrl = '${_config.wsBaseUrl}/location/track';
    debugPrint('[WS] Connecting to $nsUrl');

    _socket = io.io(
      nsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(10)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        debugPrint('[WS] Connected (id: ${_socket?.id})');
        if (!_connectionController.isClosed) {
          _connectionController.add(true);
        }
      })
      ..onDisconnect((reason) {
        debugPrint('[WS] Disconnected: $reason');
        if (!_connectionController.isClosed) {
          _connectionController.add(false);
        }
      })
      ..onConnectError((err) {
        debugPrint('[WS] Connection error: $err');
        // Some backends signal auth failure via the connect_error payload
        // rather than a post-connect `exception` event.
        if (_looksUnauthorized(err)) {
          _handleUnauthorized();
        }
      })
      ..onReconnect((_) {
        debugPrint('[WS] Reconnected');
      })
      ..onReconnectError((err) {
        debugPrint('[WS] Reconnect error: $err');
        if (_looksUnauthorized(err)) {
          _handleUnauthorized();
        }
      })
      // Backend emits `exception { error: UNAUTHORIZED, message: ... }` when
      // the token is invalid or expired. Refresh + reconnect with the new
      // token rather than leaving the socket in a half-dead state.
      ..on('exception', (data) {
        if (_looksUnauthorized(data)) {
          debugPrint('[WS] Server reported UNAUTHORIZED — refreshing');
          _handleUnauthorized();
        }
      })
      // Log ALL events from the server for debugging
      ..onAny((event, data) {
        debugPrint('[WS] Event: $event → $data');
      });
  }

  /// Disconnect from the server. Can be reconnected later with [connect].
  void disconnect() {
    _socket?.disconnect();
  }

  /// Listen for a specific event from the server.
  void on(String event, SocketEventCallback callback) {
    _socket?.on(event, callback);
  }

  /// Listen for ALL events from the server. Useful for debugging.
  /// Returns immediately if the socket isn't connected yet — attach the
  /// listener after calling [connect] completes.
  void onAnyEvent(void Function(String event, dynamic data) callback) {
    _socket?.onAny(callback);
  }

  /// Remove a listener for a specific event.
  void off(String event, [SocketEventCallback? callback]) {
    if (callback != null) {
      _socket?.off(event, callback);
    } else {
      _socket?.off(event);
    }
  }

  /// Emit an event to the server with optional data.
  void emit(String event, [dynamic data]) {
    if (_socket?.connected != true) {
      debugPrint('[WS] Cannot emit "$event" — not connected');
      return;
    }
    _socket!.emit(event, data);
  }

  /// Emit an event and await the server's ack response. Used for handlers
  /// that return a result the caller needs (e.g. `ride:accept` returns the
  /// accepted ride payload, or throws if the acceptance window has closed).
  ///
  /// Times out after [timeout] (default 8s) so a flaky socket doesn't hang
  /// the UI forever. The call also fails fast with a [StateError] if the
  /// socket is disconnected at emit time.
  Future<dynamic> emitWithAck(
    String event,
    dynamic data, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_socket?.connected != true) {
      throw StateError('Cannot emit "$event" — socket not connected');
    }
    final completer = Completer<dynamic>();
    _socket!.emitWithAck(
      event,
      data,
      ack: (response, [_]) {
        if (!completer.isCompleted) completer.complete(response);
      },
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () =>
          throw TimeoutException('No ack for "$event" within $timeout'),
    );
  }

  /// Permanently dispose the socket and close streams.
  void dispose() {
    _disposed = true;
    _socket?.dispose();
    _socket = null;
    _connectionController.close();
  }

  // ── Auth recovery ──────────────────────────────────────────────────────────

  /// Tear down the current socket, refresh the access token, and reconnect.
  /// Single-flighted so back-to-back UNAUTHORIZED events don't pile up.
  Future<void> _handleUnauthorized() {
    return _inFlightReconnect ??= () async {
      try {
        _socket?.dispose();
        _socket = null;
        if (!_connectionController.isClosed) {
          _connectionController.add(false);
        }

        final refreshed = await _refreshAccessTokenWithRetry();
        if (refreshed == null) {
          debugPrint(
            '[WS] Refresh after UNAUTHORIZED failed — staying offline',
          );
          return;
        }
        await connect();
      } finally {
        _inFlightReconnect = null;
      }
    }();
  }

  /// Refresh with a few retries — the Render free-tier backend may take
  /// 30–60s to wake from a cold start, and the very first request after
  /// app launch can also race with the iOS network stack coming up.
  /// Backs off between attempts; on a hard auth failure (e.g. refresh
  /// token revoked), [_refreshAccessToken] short-circuits and there's
  /// nothing useful to retry.
  Future<String?> _refreshAccessTokenWithRetry({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      final token = await _refreshAccessToken();
      if (token != null) return token;
      // If the refresh token itself is gone, _refreshAccessToken will have
      // already fired _onForceLogout — no point retrying.
      final stillHaveRefreshToken =
          (await _tokenStorage.readRefreshToken()) != null;
      if (!stillHaveRefreshToken) return null;
      if (i < attempts - 1) {
        final backoff = Duration(seconds: 3 * (i + 1));
        debugPrint('[WS] Refresh attempt ${i + 1} failed — retrying in '
            '${backoff.inSeconds}s');
        await Future<void>.delayed(backoff);
      }
    }
    return null;
  }

  /// Calls `/auth/refresh` and persists the new access token.
  /// Returns the new token on success, `null` on failure. On a hard auth
  /// failure (refresh token also dead), clears storage and fires
  /// [_onForceLogout] so the app routes back to sign-in.
  Future<String?> _refreshAccessToken() {
    return _inFlightRefresh ??= () async {
      try {
        final refreshToken = await _tokenStorage.readRefreshToken();
        if (refreshToken == null) {
          debugPrint('[WS] No refresh token in storage — forcing logout');
          _onForceLogout?.call();
          return null;
        }

        debugPrint('[WS] POST /auth/refresh →');
        // No explicit timeout override here — Dio's default 60s is needed to
        // ride out Render free-tier cold starts (30–60s on first hit after
        // long inactivity).
        final response = await _dio.post(
          '/auth/refresh',
          data: RefreshRequest(refreshToken: refreshToken).toJson(),
        );
        debugPrint('[WS] POST /auth/refresh ← ${response.statusCode}');

        final body = response.data as Map<String, dynamic>;
        final payload = (body['data'] is Map<String, dynamic>
            ? body['data']
            : body) as Map<String, dynamic>;

        final newAccessToken = payload['accessToken'] as String;
        // Backend rotation (B4): when the response includes a new
        // refreshToken we MUST persist it. Otherwise the next refresh
        // (from either this path or the REST auth interceptor) will reuse
        // the now-consumed refresh token and the backend will reject it
        // with REFRESH_TOKEN_REUSED → forced logout 3 minutes after login.
        final newRefreshToken = payload['refreshToken'] as String?;
        if (newRefreshToken != null && newRefreshToken != refreshToken) {
          await _tokenStorage.writeTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );
        } else {
          await _tokenStorage.writeAccessToken(newAccessToken);
        }
        debugPrint('[WS] Token refresh succeeded — wrote new access token');
        return newAccessToken;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final body = e.response?.data;
        debugPrint(
          '[WS] Token refresh DioException: type=${e.type} status=$status '
          'message=${e.message} body=$body',
        );
        // Any 4xx on /auth/refresh is terminal — the backend has rejected
        // the refresh token and the only path forward is sign-in. Don't
        // gate on specific error codes: we've seen the backend's 401 body
        // sometimes lack `error.code`, leaving the user in a zombie state
        // where every subsequent request 401s.
        if (status != null && status >= 400 && status < 500) {
          await _tokenStorage.clearTokens();
          _onForceLogout?.call();
        }
        return null;
      } on TimeoutException catch (e) {
        debugPrint('[WS] Token refresh timed out: $e');
        return null;
      } catch (e, st) {
        debugPrint('[WS] Token refresh failed: $e\n$st');
        return null;
      } finally {
        _inFlightRefresh = null;
      }
    }();
  }

  /// True if the JWT is expired or will expire within the next 30 seconds.
  /// Returns true if the token can't be parsed — we'd rather refresh
  /// unnecessarily than connect with a bad token.
  bool _isTokenExpiringSoon(String token) {
    final exp = _decodeJwtExpiry(token);
    if (exp == null) return true;
    return exp.isBefore(
      DateTime.now().toUtc().add(const Duration(seconds: 30)),
    );
  }

  /// Decode the `exp` claim from a JWT. Returns null if the token is
  /// malformed or has no `exp`.
  DateTime? _decodeJwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64.normalize(parts[1]);
      final decoded = utf8.decode(base64.decode(normalized));
      final payload = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// Heuristic: socket auth errors arrive as either a plain string or a
  /// `{ error: 'UNAUTHORIZED', message: '...' }` map depending on how the
  /// gateway throws. Match both shapes.
  bool _looksUnauthorized(dynamic data) {
    if (data is Map) {
      final err = data['error']?.toString().toUpperCase() ?? '';
      final msg = data['message']?.toString().toLowerCase() ?? '';
      if (err == 'UNAUTHORIZED' || err.contains('UNAUTHORIZED')) return true;
      if (msg.contains('invalid') && msg.contains('token')) return true;
      if (msg.contains('expired') && msg.contains('token')) return true;
    }
    final s = data?.toString().toLowerCase() ?? '';
    return s.contains('unauthorized') ||
        (s.contains('token') &&
            (s.contains('invalid') || s.contains('expired')));
  }
}
