import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import '../http/token_refresher.dart';
import '../http/token_storage.dart';
import '../realtime/realtime_socket_options.dart';
import 'app_call_service.dart';

const int _maxPendingCallSignals = 128;

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
  AuthSessionIdentity? _socketOwner;
  int _connectionGeneration = 0;
  bool _disposed = false;
  Future<void>? _inFlightReconnect;
  AuthSessionIdentity? _inFlightReconnectOwner;
  Completer<void>? _connectCompleter;
  AuthSessionIdentity? _connectOwner;
  final Set<String> _joinedCallIds = <String>{};
  final List<_PendingCallSignal> _pendingSignals = <_PendingCallSignal>[];

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

  @visibleForTesting
  AuthSessionIdentity? get socketOwnerForTesting => _socketOwner;

  Future<void> connect() async {
    if (_disposed) return;
    final observed = await _tokenStorage.readTokenSnapshot();
    final owner = observed.identity;
    var token = observed.accessToken;
    if (owner == null || token == null) {
      debugPrint('[CALL-WS] No access token — skipping call socket connect');
      return;
    }
    if (_socket?.connected == true && _socketOwner == owner) return;

    if (_socketOwner != null && _socketOwner != owner) {
      _connectionGeneration += 1;
      _socket?.dispose();
      _socket = null;
      _socketOwner = null;
      _joinedCallIds.clear();
      _pendingSignals.clear();
    }

    final existingConnection = _connectCompleter;
    if (existingConnection != null && _connectOwner == owner) {
      await existingConnection.future;
      return;
    }

    // A disconnected Socket.IO instance retains its listeners, room state and
    // exponential reconnect schedule. Reuse it instead of creating a new
    // Manager for every ICE candidate produced while the network is down.
    final existingSocket = _socket;
    if (existingSocket != null && _socketOwner == owner) {
      existingSocket.connect();
      return;
    }

    final generation = ++_connectionGeneration;
    final connection = Completer<void>();
    _connectCompleter = connection;
    _connectOwner = owner;

    try {
      if (_isTokenExpiringSoon(token)) {
        final refreshed = await _refreshWithRetry(observed);
        if (refreshed == null) {
          debugPrint('[CALL-WS] Token refresh failed — aborting connect');
          return;
        }
        token = refreshed;
      }

      final current = await _tokenStorage.readTokenSnapshot();
      if (_disposed ||
          generation != _connectionGeneration ||
          current.identity != owner ||
          current.accessToken != token) {
        return;
      }

      final nsUrl = '${_config.wsBaseUrl}/calls';
      debugPrint('[CALL-WS] Connecting to $nsUrl');

      final socket = io.io(
        nsUrl,
        buildRealtimeSocketOptions(token: token),
      );
      if (_disposed || generation != _connectionGeneration) {
        socket.dispose();
        return;
      }
      _socket = socket;
      _socketOwner = owner;

      socket
        ..onConnect((_) {
          if (!_ownsSocket(socket, owner, generation)) return;
          debugPrint('[CALL-WS] Connected (id: ${socket.id})');
          if (!connection.isCompleted) connection.complete();
          for (final callId in _joinedCallIds) {
            socket.emit('call:join', {'callId': callId});
          }
          _flushPendingSignals(socket, owner, generation);
          if (!_connectionController.isClosed) {
            _connectionController.add(true);
          }
        })
        ..onDisconnect((reason) {
          if (!_ownsSocket(socket, owner, generation)) return;
          debugPrint('[CALL-WS] Disconnected: $reason');
          if (!_connectionController.isClosed) {
            _connectionController.add(false);
          }
        })
        ..onConnectError((err) {
          if (!_ownsSocket(socket, owner, generation)) return;
          debugPrint('[CALL-WS] Connection error: $err');
          if (!connection.isCompleted) connection.complete();
          if (_looksUnauthorized(err)) {
            unawaited(
              _handleUnauthorized(socket, owner, current, generation),
            );
          }
        })
        ..onReconnectError((err) {
          if (!_ownsSocket(socket, owner, generation)) return;
          debugPrint('[CALL-WS] Reconnect error: $err');
          if (_looksUnauthorized(err)) {
            unawaited(
              _handleUnauthorized(socket, owner, current, generation),
            );
          }
        })
        ..on('exception', (data) {
          if (!_ownsSocket(socket, owner, generation)) return;
          if (_errorCode(data) == 'SOCKET_REPLACED') {
            debugPrint('[CALL-WS] Superseded socket stopped');
            socket.dispose();
            if (_ownsSocket(socket, owner, generation)) {
              _connectionGeneration += 1;
              _socket = null;
              _socketOwner = null;
              _joinedCallIds.clear();
              _pendingSignals.clear();
            }
            if (!_connectionController.isClosed) {
              _connectionController.add(false);
            }
            return;
          }
          if (_looksUnauthorized(data)) {
            debugPrint('[CALL-WS] Server reported UNAUTHORIZED — refreshing');
            unawaited(
              _handleUnauthorized(socket, owner, current, generation),
            );
          }
        })
        ..on('call:state', (data) {
          unawaited(() async {
            if (await _ownsSocketAndStorage(socket, owner, generation)) {
              _handleCallState(data);
            }
          }());
        })
        ..on('call:signal', (data) {
          unawaited(() async {
            if (await _ownsSocketAndStorage(socket, owner, generation)) {
              _handleCallSignal(data);
            }
          }());
        })
        ..on('call:participant_joined', (data) {
          unawaited(() async {
            if (await _ownsSocketAndStorage(socket, owner, generation)) {
              _handleParticipantJoined(data);
            }
          }());
        })
        ..onAny((event, data) {
          if (_ownsSocket(socket, owner, generation)) {
            _logSocketEvent(event, data);
          }
        });
      await connection.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } finally {
      if (!connection.isCompleted) connection.complete();
      if (identical(_connectCompleter, connection)) {
        _connectCompleter = null;
        _connectOwner = null;
      }
    }
  }

  Future<void> joinCall(String callId) async {
    if (callId.isEmpty) return;
    await connect();
    final socket = _socket;
    final owner = _socketOwner;
    final generation = _connectionGeneration;
    if (socket == null ||
        owner == null ||
        !await _ownsSocketAndStorage(socket, owner, generation)) {
      debugPrint('[CALL-WS] Cannot join "$callId" — socket not connected');
      return;
    }
    _joinedCallIds.add(callId);
    if (socket.connected == true) {
      socket.emit('call:join', {'callId': callId});
      return;
    }
    // onConnect emits every retained room, including this one. Keeping the
    // id in _joinedCallIds also makes reconnects automatically rejoin it.
  }

  void leaveCall(String callId) {
    unawaited(_leaveCall(callId));
  }

  Future<void> _leaveCall(String callId) async {
    final socket = _socket;
    final owner = _socketOwner;
    final generation = _connectionGeneration;
    if (socket == null ||
        owner == null ||
        !await _ownsSocketAndStorage(socket, owner, generation)) {
      return;
    }
    _joinedCallIds.remove(callId);
    _pendingSignals.removeWhere(
      (signal) => signal.owner == owner && signal.callId == callId,
    );
    if (socket.connected == true) {
      socket.emit('call:leave', {'callId': callId});
    }
  }

  void sendSignal({
    required String callId,
    required String type,
    required Map<String, dynamic> data,
  }) {
    unawaited(_sendSignal(callId: callId, type: type, data: data));
  }

  Future<void> _sendSignal({
    required String callId,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    await connect();
    final socket = _socket;
    final owner = _socketOwner;
    final generation = _connectionGeneration;
    if (socket == null ||
        owner == null ||
        !await _ownsSocketAndStorage(socket, owner, generation)) {
      return;
    }
    final signal = _PendingCallSignal(
      callId: callId,
      type: type,
      data: data,
      owner: owner,
    );
    if (socket.connected != true) {
      _queueSignal(signal);
      return;
    }
    _emitSignal(socket, signal);
  }

  void disconnect() {
    _socket?.disconnect();
  }

  void dispose() {
    _disposed = true;
    _connectionGeneration += 1;
    final socket = _socket;
    socket?.dispose();
    _socket = null;
    _socketOwner = null;
    _connectOwner = null;
    _joinedCallIds.clear();
    _pendingSignals.clear();
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

  Future<void> _handleUnauthorized(
    io.Socket socket,
    AuthSessionIdentity owner,
    AuthTokenSnapshot credentialSnapshot,
    int generation,
  ) {
    final existing = _inFlightReconnect;
    if (existing != null && _inFlightReconnectOwner == owner) {
      return existing;
    }
    late final Future<void> reconnect;
    reconnect = () async {
      try {
        if (!await _ownsSocketAndStorage(socket, owner, generation)) return;
        socket.dispose();
        if (!_ownsSocket(socket, owner, generation)) return;
        _connectionGeneration += 1;
        _socket = null;
        _socketOwner = null;
        if (!_connectionController.isClosed) {
          _connectionController.add(false);
        }

        final refreshed = await _refreshWithRetry(credentialSnapshot);
        if (refreshed == null) return;
        final current = await _tokenStorage.readTokenSnapshot();
        if (_disposed || current.identity != owner) return;
        await connect();
      } finally {
        if (identical(_inFlightReconnect, reconnect)) {
          _inFlightReconnect = null;
          _inFlightReconnectOwner = null;
        }
      }
    }();
    _inFlightReconnect = reconnect;
    _inFlightReconnectOwner = owner;
    return reconnect;
  }

  Future<String?> _refreshWithRetry(
    AuthTokenSnapshot expected, {
    int attempts = 3,
  }) async {
    for (var i = 0; i < attempts; i++) {
      final token = await _tokenRefresher.refresh(expectedSession: expected);
      if (token != null) return token;
      final current = await _tokenStorage.readTokenSnapshot();
      if (expected.identity == null || !current.belongsTo(expected.identity!)) {
        return null;
      }
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

  void _emitSignal(io.Socket socket, _PendingCallSignal signal) {
    socket.emit('call:signal', {
      'callId': signal.callId,
      'type': signal.type,
      'data': signal.data,
    });
  }

  void _queueSignal(_PendingCallSignal signal) {
    // Only the latest SDP description of each type is useful after a
    // reconnect. Replace it while retaining ICE candidates in order.
    if (signal.type == 'offer' || signal.type == 'answer') {
      _pendingSignals.removeWhere(
        (pending) =>
            pending.callId == signal.callId && pending.type == signal.type,
      );
    }
    if (_pendingSignals.length >= _maxPendingCallSignals) {
      final oldestIce = _pendingSignals.indexWhere(
        (pending) => pending.type == 'ice',
      );
      _pendingSignals.removeAt(oldestIce >= 0 ? oldestIce : 0);
      debugPrint('[CALL-WS] Pending signal buffer reached its safe limit');
    }
    _pendingSignals.add(signal);
  }

  void _flushPendingSignals(
    io.Socket socket,
    AuthSessionIdentity owner,
    int generation,
  ) {
    if (!_ownsSocket(socket, owner, generation) ||
        socket.connected != true ||
        _pendingSignals.isEmpty) {
      return;
    }
    final pending = List<_PendingCallSignal>.of(_pendingSignals);
    _pendingSignals.clear();
    var replayed = 0;
    for (final signal in pending) {
      if (signal.owner != owner) continue;
      if (!_joinedCallIds.contains(signal.callId)) continue;
      _emitSignal(socket, signal);
      replayed += 1;
    }
    debugPrint('[CALL-WS] Replayed $replayed queued signal(s)');
  }

  String _errorCode(dynamic data) {
    if (data is Map) return data['error']?.toString().toUpperCase() ?? '';
    return '';
  }

  bool _ownsSocket(
    io.Socket socket,
    AuthSessionIdentity owner,
    int generation,
  ) =>
      !_disposed &&
      generation == _connectionGeneration &&
      identical(_socket, socket) &&
      _socketOwner == owner;

  Future<bool> _ownsSocketAndStorage(
    io.Socket socket,
    AuthSessionIdentity owner,
    int generation,
  ) async {
    if (!_ownsSocket(socket, owner, generation)) return false;
    final current = await _tokenStorage.readTokenSnapshot();
    return _ownsSocket(socket, owner, generation) && current.belongsTo(owner);
  }

  @visibleForTesting
  int get pendingSignalCount => _pendingSignals.length;

  @visibleForTesting
  List<String> get pendingSignalTypes =>
      _pendingSignals.map((signal) => signal.type).toList(growable: false);

  Map<String, dynamic>? _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}

class _PendingCallSignal {
  const _PendingCallSignal({
    required this.callId,
    required this.type,
    required this.data,
    required this.owner,
  });

  final String callId;
  final String type;
  final Map<String, dynamic> data;
  final AuthSessionIdentity owner;
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
