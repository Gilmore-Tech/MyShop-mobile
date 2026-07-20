import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import '../http/token_refresher.dart';
import '../http/token_storage.dart';
import 'app_call_service.dart';

/// Lightweight Socket.IO client for the `/calls` namespace.
///
/// REST owns call lifecycle persistence; this socket mirrors live state to the
/// already-open call screen so one participant's decline/end immediately moves
/// the other participant out of the ringing UI.
class AppCallSocketService {
  AppCallSocketService({
    required ApiConfig config,
    required TokenStorage tokenStorage,
    required TokenRefresher tokenRefresher,
  })  : _config = config,
        _tokenStorage = tokenStorage,
        _tokenRefresher = tokenRefresher;

  final ApiConfig _config;
  final TokenStorage _tokenStorage;
  final TokenRefresher _tokenRefresher;

  io.Socket? _socket;
  bool _disposed = false;
  Future<void>? _inFlightReconnect;
  Completer<void>? _connectCompleter;
  final Set<String> _joinedCallIds = <String>{};

  final _sessionController = StreamController<AppCallSession>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _signalController = StreamController<AppCallSignal>.broadcast();
  final _participantJoinedController = StreamController<String>.broadcast();

  Stream<AppCallSession> get sessionStream => _sessionController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<AppCallSignal> get signalStream => _signalController.stream;
  Stream<String> get participantJoinedStream =>
      _participantJoinedController.stream;

  bool get isConnected => _socket?.connected ?? false;

  Future<void> connect() async {
    if (_disposed) return;
    if (_socket?.connected == true) return;
    final existingConnection = _connectCompleter;
    if (existingConnection != null) {
      await existingConnection.future;
      return;
    }

    final connection = Completer<void>();
    _connectCompleter = connection;

    try {
      var token = await _tokenStorage.readAccessToken();
      if (token == null) {
        debugPrint('[CALL-WS] No access token — skipping call socket connect');
        return;
      }

      if (_isTokenExpiringSoon(token)) {
        final refreshed = await _refreshWithRetry();
        if (refreshed == null) {
          debugPrint('[CALL-WS] Token refresh failed — aborting connect');
          return;
        }
        token = refreshed;
      }

      _socket?.dispose();

      final nsUrl = '${_config.wsBaseUrl}/calls';
      debugPrint('[CALL-WS] Connecting to $nsUrl');

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
          debugPrint('[CALL-WS] Connected (id: ${_socket?.id})');
          if (!connection.isCompleted) connection.complete();
          for (final callId in _joinedCallIds) {
            _socket?.emit('call:join', {'callId': callId});
          }
          if (!_connectionController.isClosed) {
            _connectionController.add(true);
          }
        })
        ..onDisconnect((reason) {
          debugPrint('[CALL-WS] Disconnected: $reason');
          if (!_connectionController.isClosed) {
            _connectionController.add(false);
          }
        })
        ..onConnectError((err) {
          debugPrint('[CALL-WS] Connection error: $err');
          if (!connection.isCompleted) connection.complete();
          if (_looksUnauthorized(err)) {
            _handleUnauthorized();
          }
        })
        ..onReconnectError((err) {
          debugPrint('[CALL-WS] Reconnect error: $err');
          if (_looksUnauthorized(err)) {
            _handleUnauthorized();
          }
        })
        ..on('exception', (data) {
          if (_looksUnauthorized(data)) {
            debugPrint('[CALL-WS] Server reported UNAUTHORIZED — refreshing');
            _handleUnauthorized();
          }
        })
        ..on('call:state', _handleCallState)
        ..on('call:signal', _handleCallSignal)
        ..on('call:participant_joined', _handleParticipantJoined)
        ..onAny((event, data) {
          _logSocketEvent(event, data);
        });
      await connection.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } finally {
      if (!connection.isCompleted) connection.complete();
      if (identical(_connectCompleter, connection)) {
        _connectCompleter = null;
      }
    }
  }

  Future<void> joinCall(String callId) async {
    if (callId.isEmpty) return;
    _joinedCallIds.add(callId);
    if (_socket?.connected == true) {
      _socket!.emit('call:join', {'callId': callId});
      return;
    }
    await connect();
    if (_socket?.connected != true) {
      debugPrint('[CALL-WS] Cannot join "$callId" — socket not connected');
    }
    // onConnect emits every retained room, including this one. Keeping the
    // id in _joinedCallIds also makes reconnects automatically rejoin it.
  }

  void leaveCall(String callId) {
    _joinedCallIds.remove(callId);
    if (_socket?.connected != true) return;
    _socket!.emit('call:leave', {'callId': callId});
  }

  void sendSignal({
    required String callId,
    required String type,
    required Map<String, dynamic> data,
  }) {
    if (_socket?.connected != true) return;
    _socket!.emit('call:signal', {
      'callId': callId,
      'type': type,
      'data': data,
    });
  }

  void disconnect() {
    _socket?.disconnect();
  }

  void dispose() {
    _disposed = true;
    _socket?.dispose();
    _socket = null;
    _joinedCallIds.clear();
    _sessionController.close();
    _connectionController.close();
    _signalController.close();
    _participantJoinedController.close();
  }

  void _handleCallState(dynamic data) {
    final json = _asJsonMap(data);
    if (json == null) return;
    if (!_sessionController.isClosed) {
      _sessionController.add(AppCallSession.fromJson(json));
    }
  }

  void _handleCallSignal(dynamic data) {
    final json = _asJsonMap(data);
    if (json == null || _signalController.isClosed) return;
    final signal = AppCallSignal.fromJson(json);
    if (signal.callId.isNotEmpty && signal.type.isNotEmpty) {
      _signalController.add(signal);
    }
  }

  void _handleParticipantJoined(dynamic data) {
    final json = _asJsonMap(data);
    final callId = json?['callId'] as String?;
    if (callId == null || _participantJoinedController.isClosed) return;
    _participantJoinedController.add(callId);
  }

  void _logSocketEvent(String event, dynamic data) {
    final json = _asJsonMap(data);
    final callId = json?['callId'] ?? json?['id'];
    switch (event) {
      case 'call:state':
        debugPrint(
          '[CALL-WS] Event: call:state callId=$callId '
          'status=${json?['status']} rtcProvider=${json?['rtcProvider']}',
        );
      case 'call:signal':
        // SDP, ICE candidates, and TURN credentials can contain sensitive
        // network details. Log only correlation and signal type.
        debugPrint(
          '[CALL-WS] Event: call:signal callId=$callId '
          'type=${json?['type']}',
        );
      case 'call:participant_joined' || 'call:participant_left':
        debugPrint('[CALL-WS] Event: $event callId=$callId');
      default:
        debugPrint('[CALL-WS] Event: $event');
    }
  }

  Future<void> _handleUnauthorized() {
    return _inFlightReconnect ??= () async {
      try {
        _socket?.dispose();
        _socket = null;
        if (!_connectionController.isClosed) {
          _connectionController.add(false);
        }

        final refreshed = await _refreshWithRetry();
        if (refreshed == null) return;
        await connect();
      } finally {
        _inFlightReconnect = null;
      }
    }();
  }

  Future<String?> _refreshWithRetry({int attempts = 3}) async {
    for (var i = 0; i < attempts; i++) {
      final token = await _tokenRefresher.refresh();
      if (token != null) return token;
      final stillHaveRefreshToken =
          (await _tokenStorage.readRefreshToken()) != null;
      if (!stillHaveRefreshToken) return null;
      if (i < attempts - 1) {
        await Future<void>.delayed(Duration(seconds: 3 * (i + 1)));
      }
    }
    return null;
  }

  bool _isTokenExpiringSoon(String token) {
    final exp = _decodeJwtExpiry(token);
    if (exp == null) return true;
    return exp.isBefore(
      DateTime.now().toUtc().add(const Duration(seconds: 30)),
    );
  }

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

  bool _looksUnauthorized(dynamic err) {
    final text = err.toString().toLowerCase();
    if (text.contains('unauthorized') || text.contains('jwt')) return true;
    if (err is Map) {
      final error = err['error']?.toString().toUpperCase();
      return error == 'UNAUTHORIZED' || error == 'TOKEN_EXPIRED';
    }
    return false;
  }

  Map<String, dynamic>? _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}

class AppCallSignal {
  const AppCallSignal({
    required this.callId,
    required this.type,
    required this.data,
  });

  factory AppCallSignal.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AppCallSignal(
      callId: json['callId'] as String? ?? '',
      type: json['type'] as String? ?? '',
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{},
    );
  }

  final String callId;
  final String type;
  final Map<String, dynamic> data;
}
