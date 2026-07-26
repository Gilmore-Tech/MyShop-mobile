import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import '../http/token_refresher.dart';
import '../http/token_storage.dart';
import '../realtime/realtime_socket_options.dart';

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
    required TokenRefresher tokenRefresher,
  })  : _config = config,
        _tokenStorage = tokenStorage,
        _tokenRefresher = tokenRefresher;

  // v2 includes the native ActivityKit receipt path used by iOS remote starts.
  static const int rideOfferReceiptVersion = 2;

  final ApiConfig _config;
  final TokenStorage _tokenStorage;
  final TokenRefresher _tokenRefresher;

  io.Socket? _socket;
  bool _disposed = false;

  // Single-flight guard so back-to-back UNAUTHORIZED events don't fan
  // out into multiple concurrent reconnect cycles. Refresh dedup is
  // handled by [TokenRefresher] (process-wide, shared with the REST
  // auth interceptor).
  Future<void>? _inFlightReconnect;

  /// App-level callback invoked synchronously every time a new
  /// underlying [io.Socket] is created in [connect]. The app uses this
  /// to (re-)attach domain event handlers (`job:new`, `ride:state`,
  /// etc.) — without it, the lifecycle observer's reconnect path
  /// disposes the old socket and the new one comes up with zero
  /// handlers because `connect()` ran outside the Riverpod provider
  /// that owned the original `socket.on(...)` calls.
  void Function()? _afterCreate;

  /// Register a callback that fires on every fresh underlying socket
  /// (initial connect AND post-dispose reconnects). Call once at
  /// app/socket bootstrap; the callback persists for the lifetime of
  /// the service.
  void onAfterCreate(void Function() callback) {
    _afterCreate = callback;
  }

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
    // Refresh delegates to the shared [TokenRefresher] (single-flight
    // across REST + WS), so a concurrent REST 401 also kicking off
    // /auth/refresh just awaits the same future instead of racing the
    // refresh token through the backend and one of them eating
    // REFRESH_TOKEN_REUSED.
    if (_isTokenExpiringSoon(token)) {
      debugPrint('[WS] Access token expired/expiring — refreshing pre-connect');
      final refreshed = await _refreshWithRetry();
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
      buildRealtimeSocketOptions(
        token: token,
        auth: {
          // The server joins only receipt-capable provider builds to the
          // v2 ride-offer room. Older installs therefore cannot receive an
          // actionable envelope whose accept contract they do not support.
          'offerReceiptVersion': rideOfferReceiptVersion,
        },
      ),
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
        if (_errorCode(data) == 'SOCKET_REPLACED') {
          debugPrint('[WS] Superseded socket stopped');
          _socket?.dispose();
          _socket = null;
          return;
        }
        if (_looksUnauthorized(data)) {
          debugPrint('[WS] Server reported UNAUTHORIZED — refreshing');
          _handleUnauthorized();
        }
      })
      // Log ALL events from the server for debugging
      ..onAny((event, data) {
        debugPrint('[WS] Event: $event → $data');
      });

    // Re-bind app-level handlers (`job:new`, `ride:state`, etc.) to the
    // freshly-created io.Socket. Critical for the lifecycle resume path
    // — without this, every background→resume cycle drops every domain
    // listener and the artisan stops seeing job requests until they
    // toggle online/offline.
    _afterCreate?.call();
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

        final refreshed = await _refreshWithRetry();
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

  /// Wraps [TokenRefresher.refresh] in a small retry loop to ride out
  /// Render free-tier cold starts (30–60s on first hit after long idle)
  /// and transient network blips during app launch. The refresher's
  /// single-flight already coalesces concurrent callers, so retrying
  /// here is safe — overlapping callers await the same in-flight future.
  /// Bails immediately when the refresh token itself is gone (refresher
  /// has already fired onForceLogout in that case).
  Future<String?> _refreshWithRetry({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      final token = await _tokenRefresher.refresh();
      if (token != null) return token;
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

  String _errorCode(dynamic data) {
    if (data is Map) return data['error']?.toString().toUpperCase() ?? '';
    return '';
  }
}
