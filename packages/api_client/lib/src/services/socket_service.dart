import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import '../http/token_storage.dart';

/// Callback for when a Socket.IO event is received.
typedef SocketEventCallback = void Function(dynamic data);

/// Manages the Socket.IO connection to the MyShop backend.
///
/// Handles:
/// - Authenticated connection with Bearer token
/// - Automatic reconnection on disconnect
/// - Event subscription/unsubscription
/// - Connection lifecycle (connect/disconnect/dispose)
class SocketService {
  SocketService({
    required ApiConfig config,
    required TokenStorage tokenStorage,
  })  : _config = config,
        _tokenStorage = tokenStorage;

  final ApiConfig _config;
  final TokenStorage _tokenStorage;

  io.Socket? _socket;
  bool _disposed = false;

  final _connectionController = StreamController<bool>.broadcast();

  /// Stream that emits `true` when connected, `false` when disconnected.
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Whether the socket is currently connected.
  bool get isConnected => _socket?.connected ?? false;

  /// Connect to the Socket.IO server with the stored access token.
  Future<void> connect() async {
    if (_disposed) return;
    if (_socket?.connected == true) return;

    final token = await _tokenStorage.readAccessToken();
    if (token == null) {
      debugPrint('[WS] No access token — skipping socket connect');
      return;
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
      })
      ..onReconnect((_) {
        debugPrint('[WS] Reconnected');
      })
      ..onReconnectError((err) {
        debugPrint('[WS] Reconnect error: $err');
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

  /// Permanently dispose the socket and close streams.
  void dispose() {
    _disposed = true;
    _socket?.dispose();
    _socket = null;
    _connectionController.close();
  }
}
