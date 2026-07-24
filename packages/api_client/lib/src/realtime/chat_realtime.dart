import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'dart:async';
import 'dart:convert';

import 'package:shared_models/shared_models.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import '../http/token_refresher.dart';
import '../http/token_storage.dart';
import 'realtime_socket_options.dart';

/// Real-time client for the `/chat` Socket.IO namespace.
///
/// This is a separate connection from the main `/location/track` namespace
/// (see [SocketService]) — the spec is explicit: *"Different namespace from
/// the main socket — open a second connection; do not multiplex."* The
/// lifecycle mirrors `SocketService` so both live and die under the same
/// auth-recovery rules: pre-connect token refresh when the JWT is about to
/// expire, single-flighted refresh-and-reconnect on `UNAUTHORIZED`, and
/// 10-attempt reconnection with a 2 s base delay.
///
/// Phase 2 owns the transport: connect, join, ack-based send/read,
/// stream out the three inbound events, and re-join after a reconnect.
/// Phase 3 wraps this with the higher-level orchestrator (REST history
/// fetch, optimistic outbox, ack-timeout REST fallback, dedupe, persistence).
class ChatRealtime {
  ChatRealtime({
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

  // Single-flight guard for reconnect — refresh dedup is handled by
  // [TokenRefresher] (process-wide, shared with REST + main WS). Before
  // this was wired in, ChatRealtime's private refresh path raced the
  // shared refresher through the backend's refresh-token rotation and
  // the loser ate REFRESH_TOKEN_REUSED → forced logout.
  Future<void>? _inFlightReconnect;

  ChatChannel? _channel;

  // Inbound event streams
  final _connectionController = StreamController<bool>.broadcast();
  final _incomingMessagesController = StreamController<ChatMessage>.broadcast();
  final _readReceiptsController = StreamController<ChatReadReceipt>.broadcast();
  final _channelClosedController =
      StreamController<ChatChannelClosedEvent>.broadcast();
  final _typingUpdatesController =
      StreamController<ChatTypingUpdate>.broadcast();

  /// True when the underlying socket reports `connected`. Useful for
  /// gating UI affordances (e.g. a tiny green dot in the chat header).
  bool get isConnected => _socket?.connected ?? false;

  /// Emits `true` on connect, `false` on disconnect. Phase 3 listens here
  /// to trigger the reconcile-on-reconnect history re-fetch.
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Every new message the server pushed for the joined room — including
  /// our own (the backend broadcasts to the entire room). Callers must
  /// dedupe by [ChatMessage.id] since they will also receive the ack-side
  /// of their own send.
  Stream<ChatMessage> get incomingMessages =>
      _incomingMessagesController.stream;

  /// Other-side read receipts for our messages.
  Stream<ChatReadReceipt> get readReceipts => _readReceiptsController.stream;

  /// Booking transitioned to completed/cancelled — the channel is now
  /// read-only. UI should lock the composer + show the closed banner.
  Stream<ChatChannelClosedEvent> get channelClosed =>
      _channelClosedController.stream;

  /// `chat:typing:update` events from the room. Includes both starts
  /// (`isTyping: true`) and stops (`isTyping: false`); the orchestrator
  /// filters by channel + non-self before exposing a `Stream<bool>` to
  /// the UI.
  Stream<ChatTypingUpdate> get typingUpdates => _typingUpdatesController.stream;

  /// The currently joined channel, if any. `null` between [disconnect] and
  /// the next [joinChannel].
  ChatChannel? get currentChannel => _channel;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Open the `/chat` socket. Idempotent — safe to call repeatedly. If the
  /// stored access token is expired or expiring soon, refreshes first; if
  /// the refresh fails, returns silently (auth state will route the user
  /// back to sign-in via [onForceLogout]).
  Future<void> connect() async {
    if (_disposed) return;
    if (_socket?.connected == true) return;

    var token = await _tokenStorage.readAccessToken();
    if (token == null) {
      debugLog(() => '[CHAT-WS] No access token — skipping connect');
      return;
    }

    if (_isTokenExpiringSoon(token)) {
      debugLog(
        () => '[CHAT-WS] Token expired/expiring — refreshing pre-connect',
      );
      // Shared TokenRefresher (single-flight across REST + main WS +
      // chat WS), so a concurrent refresh from any other path just
      // awaits the same future instead of racing the rotating token
      // through the backend.
      final refreshed = await _tokenRefresher.refresh();
      if (refreshed == null) {
        debugLog(() => '[CHAT-WS] Pre-connect refresh failed — aborting');
        return;
      }
      token = refreshed;
    }

    _socket?.dispose();

    final nsUrl = '${_config.wsBaseUrl}/chat';
    debugLog(() => '[CHAT-WS] Connecting to $nsUrl');

    _socket = io.io(
      nsUrl,
      buildRealtimeSocketOptions(token: token),
    );

    _socket!
      ..onConnect((_) {
        debugLog(() => '[CHAT-WS] Connected');
        if (!_connectionController.isClosed) _connectionController.add(true);
        // If we had a channel before the disconnect, automatically re-join
        // so server-side delivery resumes without the orchestrator having
        // to remember/re-issue it.
        //
        // Longer timeout than user-initiated joins: auto-rejoin often
        // fires right after a backend cold-start (Render free tier) where
        // 5s is too tight. Catch the throw — this is fire-and-forget, so
        // an uncaught ChatRealtimeException would surface as a top-level
        // async error. On failure, live delivery for this booking is
        // paused until the next reconnect cycle or until the user re-opens
        // chat (which calls openChannel → fresh join); REST fallbacks keep
        // send/read working in the meantime.
        final pending = _channel;
        if (pending != null) {
          unawaited(
            _emitJoin(
              pending.bookingType,
              pending.bookingId,
              timeout: const Duration(seconds: 15),
            ).catchError((Object e) {
              debugLog(
                () => '[CHAT-WS] Auto-rejoin failed type=${e.runtimeType}',
              );
            }),
          );
        }
      })
      ..onDisconnect((_) {
        debugLog(() => '[CHAT-WS] Disconnected');
        if (!_connectionController.isClosed) _connectionController.add(false);
      })
      ..onConnectError((err) {
        debugLog(() => '[CHAT-WS] Connect error type=${err.runtimeType}');
        if (_looksUnauthorized(err)) _handleUnauthorized();
      })
      ..onReconnect((_) {
        debugLog(() => '[CHAT-WS] Reconnected');
      })
      ..onReconnectError((err) {
        debugLog(() => '[CHAT-WS] Reconnect error type=${err.runtimeType}');
        if (_looksUnauthorized(err)) _handleUnauthorized();
      })
      ..on('exception', (data) {
        final code = _errorCode(data);
        debugLog(
          () => '[CHAT-WS] Server exception code=${_safeDiagnosticCode(code)}',
        );
        if (code == 'SOCKET_REPLACED') {
          debugLog(() => '[CHAT-WS] Superseded socket stopped');
          _socket?.dispose();
          _socket = null;
          return;
        }
        if (_looksUnauthorized(data)) {
          _handleUnauthorized();
        }
      })
      ..on('chat:message:received', (data) {
        if (data is Map<String, dynamic>) {
          try {
            _incomingMessagesController.add(ChatMessage.fromJson(data));
          } catch (e) {
            debugLog(
              () =>
                  '[CHAT-WS] Invalid chat:message:received type=${e.runtimeType}',
            );
          }
        }
      })
      ..on('chat:read:receipt', (data) {
        if (data is Map<String, dynamic>) {
          try {
            _readReceiptsController.add(ChatReadReceipt.fromJson(data));
          } catch (e) {
            debugLog(
              () => '[CHAT-WS] Invalid chat:read:receipt type=${e.runtimeType}',
            );
          }
        }
      })
      ..on('chat:typing:update', (data) {
        if (data is Map<String, dynamic>) {
          try {
            _typingUpdatesController.add(ChatTypingUpdate.fromJson(data));
          } catch (e) {
            debugLog(
              () =>
                  '[CHAT-WS] Invalid chat:typing:update type=${e.runtimeType}',
            );
          }
        }
      })
      ..on('chat:channel:closed', (data) {
        if (data is Map<String, dynamic>) {
          try {
            final evt = ChatChannelClosedEvent.fromJson(data);
            _channelClosedController.add(evt);
            // Mirror the closed state on the cached channel so callers
            // reading `currentChannel` see the lock state too.
            final c = _channel;
            if (c != null &&
                c.bookingType == evt.bookingType &&
                c.bookingId == evt.bookingId) {
              _channel = c.copyWith(status: ChatChannelStatus.closed);
            }
          } catch (e) {
            debugLog(
              () =>
                  '[CHAT-WS] Invalid chat:channel:closed type=${e.runtimeType}',
            );
          }
        }
      });
  }

  /// Hard-disconnect. The Phase 3 orchestrator calls this on logout and
  /// when the user navigates away from the chat surface for long enough
  /// that keeping the socket open is wasteful.
  void disconnect() {
    _socket?.disconnect();
  }

  /// Permanently dispose. After this the instance is unusable; create a
  /// new one if needed.
  void dispose() {
    _disposed = true;
    _channel = null;
    _socket?.dispose();
    _socket = null;
    _connectionController.close();
    _incomingMessagesController.close();
    _readReceiptsController.close();
    _channelClosedController.close();
    _typingUpdatesController.close();
  }

  // ── Channel ────────────────────────────────────────────────────────────────

  /// Join the room for `(bookingType, bookingId)`. Connects the socket
  /// first if it isn't already up.
  ///
  /// Throws [ChatRealtimeException] on `NOT_A_PARTICIPANT`,
  /// `BOOKING_NOT_FOUND`, or `CHAT_CHANNEL_CLOSED`.
  Future<void> joinChannel(
    ChatBookingType bookingType,
    String bookingId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected) await connect();
    _channel = ChatChannel(bookingType: bookingType, bookingId: bookingId);
    await _emitJoin(bookingType, bookingId, timeout: timeout);
  }

  Future<void> _emitJoin(
    ChatBookingType bookingType,
    String bookingId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_socket?.connected != true) {
      throw const ChatRealtimeException(
        code: ChatErrorCodes.notConnected,
        message: 'Chat socket is not connected.',
      );
    }
    final ack = await _emitWithAck(
      'chat:join',
      {
        'bookingType': bookingType.wire,
        'bookingId': bookingId,
      },
      timeout: timeout,
    );
    _checkAck(ack);
    if (ack is Map && ack['joined'] == true) {
      // Refresh the cached channel — joining replaces any prior one.
      _channel = ChatChannel(
        bookingType: bookingType,
        bookingId: bookingId,
      );
      return;
    }
    throw const ChatRealtimeException(
      code: ChatErrorCodes.unknown,
      message: 'Server did not confirm chat join.',
    );
  }

  /// Forget the current channel locally. Doesn't send anything to the
  /// server (the spec has no `chat:leave` event); the backend evicts the
  /// socket from the room when the connection closes or another channel
  /// is joined.
  void leaveChannel() {
    _channel = null;
  }

  /// Emit `chat:typing` with the current channel context.
  ///
  /// Fire-and-forget — typing is best-effort, the backend doesn't ack.
  /// No-op when there's no joined channel or the socket isn't connected;
  /// the orchestrator already drops typing pings in those cases via its
  /// debounce/idle logic, so this is just a defensive no-op.
  ///
  /// The orchestrator's [ChatController.notifyTyping] handles the
  /// debounce (1 emit per 3s while typing) and the local idle auto-stop
  /// (3s after the last keystroke). The server's 6s safety net is the
  /// floor — never the primary signal.
  void sendTyping({required bool isTyping}) {
    final channel = _channel;
    if (channel == null) return;
    if (_socket?.connected != true) return;
    _socket!.emit('chat:typing', {
      'bookingType': channel.bookingType.wire,
      'bookingId': channel.bookingId,
      'isTyping': isTyping,
    });
  }

  // ── Send / read ────────────────────────────────────────────────────────────

  /// Emit a `chat:message` for the currently joined channel. Returns the
  /// saved [ChatMessage] from the ack — Phase 3 swaps the optimistic
  /// `tmp_…` id for this server-assigned id.
  ///
  /// Throws [ChatRealtimeException] with [ChatErrorCodes.ackTimeout] on
  /// timeout (Phase 3 then falls back to the REST POST), or with the
  /// backend's error code on a failed ack.
  Future<ChatMessage> sendMessage({
    required String message,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final channel = _channel;
    if (channel == null) {
      throw const ChatRealtimeException(
        code: ChatErrorCodes.unknown,
        message: 'No active channel — call joinChannel first.',
      );
    }
    final ack = await _emitWithAck(
      'chat:message',
      {
        'bookingType': channel.bookingType.wire,
        'bookingId': channel.bookingId,
        'message': message,
      },
      timeout: timeout,
    );
    _checkAck(ack);
    if (ack is Map<String, dynamic>) {
      return ChatMessage.fromJson(ack);
    }
    throw const ChatRealtimeException(
      code: ChatErrorCodes.unknown,
      message: 'Unexpected ack shape from chat:message.',
    );
  }

  /// Emit `chat:message:read`. Returns the server-stamped `readAt`.
  Future<DateTime> markRead({
    required String messageId,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final ack = await _emitWithAck(
      'chat:message:read',
      {'messageId': messageId},
      timeout: timeout,
    );
    _checkAck(ack);
    if (ack is Map &&
        ack['readAt'] is String &&
        DateTime.tryParse(ack['readAt'] as String) != null) {
      return DateTime.parse(ack['readAt'] as String);
    }
    // Idempotent endpoint — if backend acks success without echoing
    // `readAt`, stamp now so the UI flips its tick.
    return DateTime.now().toUtc();
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Emit + await ack with a timeout. Mirrors `SocketService.emitWithAck`
  /// but throws a typed [ChatRealtimeException] on timeout so the
  /// orchestrator can switch to its REST fallback by switching on
  /// [ChatErrorCodes.ackTimeout].
  Future<dynamic> _emitWithAck(
    String event,
    dynamic data, {
    required Duration timeout,
  }) async {
    if (_socket?.connected != true) {
      throw const ChatRealtimeException(
        code: ChatErrorCodes.notConnected,
        message: 'Chat socket is not connected.',
      );
    }
    final completer = Completer<dynamic>();
    _socket!.emitWithAck(
      event,
      data,
      ack: (response, [_]) {
        if (!completer.isCompleted) completer.complete(response);
      },
    );
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw ChatRealtimeException(
        code: ChatErrorCodes.ackTimeout,
        message: 'No ack for "$event" within ${timeout.inSeconds}s.',
      );
    }
  }

  /// Inspect an ack and convert any error envelope into a typed throw.
  /// Backend errors come back as either:
  ///   - first arg: `{ error: 'CODE', message: '...' }` (most common)
  ///   - first arg: a string starting with `'error'` (rare; legacy)
  /// Success acks are passed through unchanged.
  void _checkAck(dynamic ack) {
    if (ack is Map) {
      final err = ack['error'];
      if (err is String && err.isNotEmpty) {
        throw ChatRealtimeException(
          code: err,
          message: ack['message']?.toString() ?? 'Chat operation failed.',
        );
      }
    }
    if (ack is String && ack.toLowerCase().startsWith('error')) {
      throw ChatRealtimeException(
        code: ChatErrorCodes.unknown,
        message: ack,
      );
    }
  }

  // ── Auth recovery (mirrors SocketService) ──────────────────────────────────

  Future<void> _handleUnauthorized() {
    return _inFlightReconnect ??= () async {
      try {
        _socket?.dispose();
        _socket = null;
        if (!_connectionController.isClosed) _connectionController.add(false);

        final refreshed = await _tokenRefresher.refresh();
        if (refreshed == null) {
          debugLog(
            () =>
                '[CHAT-WS] Refresh after UNAUTHORIZED failed — staying offline',
          );
          return;
        }
        await connect();
      } finally {
        _inFlightReconnect = null;
      }
    }();
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

  String _safeDiagnosticCode(String code) {
    return switch (code) {
      'SOCKET_REPLACED' || 'UNAUTHORIZED' || 'TOKEN_EXPIRED' => code,
      _ => 'unknown',
    };
  }
}

/// Typed exception surfaced by [ChatRealtime]. [code] is one of the
/// constants in [ChatErrorCodes] (server-side codes when the backend
/// rejected the operation, plus the local-only `CHAT_ACK_TIMEOUT` and
/// `CHAT_NOT_CONNECTED`).
class ChatRealtimeException implements Exception {
  const ChatRealtimeException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'ChatRealtimeException($code): $message';
}
