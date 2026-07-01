import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';

import '../models/api_exception.dart';
import '../services/chat_service.dart';
import 'chat_outbox.dart';
import 'chat_realtime.dart';

/// Higher-level orchestrator that combines the REST [ChatService], the
/// realtime [ChatRealtime] socket, and a persistent [ChatOutbox] into the
/// single API the UI consumes.
///
/// Behaviour summary:
///
///   - **Open**: connects realtime, joins the room, fetches history via
///     REST, hydrates an in-memory list, and replays any failed outbox
///     items from a previous session as ghosted bubbles ready to retry.
///   - **Send**: optimistic-appends a `tmp_…` bubble, persists it to the
///     outbox, then races a `chat:message` socket emit (3s ack timeout)
///     against a REST POST fallback. Whichever wins swaps the temp id
///     for the server id and removes the outbox item.
///   - **Read**: fires `chat:message:read` (3s ack), falls back to PATCH.
///     Only emitted for the recipient's messages — own messages and
///     already-read messages are skipped silently.
///   - **Reconnect**: when the underlying socket drops and comes back,
///     re-joins (handled inside [ChatRealtime]) AND re-fetches history
///     to backfill anything missed during the gap. Dedupe on id.
///   - **Channel close**: surfaces `chat:channel:closed` as an immutable
///     channel state; UI locks the composer; outbox is cleared.
///   - **Logout / dispose**: tears down all stream subs and clears the
///     in-memory state. The outbox stays on disk so a returning user
///     sees their unsent message preserved.
class ChatController {
  ChatController({
    required ChatService rest,
    required ChatRealtime realtime,
    required ChatOutbox outbox,
    required String selfUserId,
    required ChatSenderRole selfRole,
    @visibleForTesting Random? random,
  })  : _rest = rest,
        _realtime = realtime,
        _outbox = outbox,
        _selfUserId = selfUserId,
        _selfRole = selfRole,
        _random = random ?? Random();

  final ChatService _rest;
  final ChatRealtime _realtime;
  final ChatOutbox _outbox;
  final String _selfUserId;

  /// The role the local user is currently signed in as. Pinned at
  /// controller-construction time. Critical for "is this my message?"
  /// resolution on a device where the same human runs both apps with
  /// the same `selfUserId` — without role-awareness, every incoming
  /// message looked like it came from the local user and rendered on
  /// the right-hand side. See Phase 1/2 hotfix history in CHANGELOG.
  final ChatSenderRole _selfRole;
  final Random _random;

  // ── Per-channel state ─────────────────────────────────────────────────────
  ChatChannel? _channel;

  /// Keyed by [ChatMessage.id] (or `tempId` while pending). Insertion order
  /// is preserved by Dart's `LinkedHashMap`, which we lean on for the
  /// chronological message list.
  final Map<String, ChatMessage> _messages = {};

  /// Tracks which optimistic temp ids are still in-flight or have failed
  /// outright. UI uses `failedIds.contains(id)` to decide between the
  /// pending tick and the "!" retry overlay.
  final Set<String> _pendingTempIds = {};
  final Set<String> _failedTempIds = {};

  // Stream controllers — broadcast so multiple widgets can subscribe.
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final _channelController = StreamController<ChatChannel?>.broadcast();
  final _failedIdsController = StreamController<Set<String>>.broadcast();
  final _unreadCountController = StreamController<int>.broadcast();
  final _peerTypingController = StreamController<bool>.broadcast();

  // Realtime stream subs — replaced on each openChannel.
  StreamSubscription<ChatMessage>? _incomingSub;
  StreamSubscription<ChatReadReceipt>? _readReceiptSub;
  StreamSubscription<ChatChannelClosedEvent>? _closedSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<ChatTypingUpdate>? _typingSub;

  // ── Typing state ──────────────────────────────────────────────────────────
  /// True when we last emitted `chat:typing { isTyping: true }` and haven't
  /// emitted `false` since. Drives the debounce decision in [notifyTyping].
  bool _ourTypingState = false;

  /// When we last emitted `isTyping: true`. Lets us debounce re-emits to
  /// once every 3 s while the user keeps typing — the server's auto-stop
  /// is 6 s, so 3 s is comfortably below it.
  DateTime? _lastTrueEmittedAt;

  /// Fires 3 s after the last [notifyTyping] true-call with no further
  /// activity → emit `false` automatically so the peer's indicator
  /// disappears the moment the user stops typing (rather than after the
  /// server's 6 s safety net would catch it).
  Timer? _localIdleTimer;

  /// User id of the peer whose indicator we're currently showing, or null.
  /// Used to filter out-of-band stop events and to clear the indicator
  /// when that user sends a message.
  String? _typingPeerUserId;

  /// Mirror of the server's 6 s safety net on the receive side. Guards
  /// against an upstream `isTyping: true` whose matching `false` somehow
  /// never arrives (rare — disconnect/auto-stop should cover it).
  Timer? _peerTypingClearTimer;

  // 3 s primary signal, slightly under the server's 6 s floor.
  static const _typingDebounce = Duration(seconds: 3);
  static const _typingIdle = Duration(seconds: 3);
  // 7 s = server's 6 s auto-stop + 1 s for the broadcast hop.
  static const _peerTypingClearWindow = Duration(seconds: 7);

  bool _disposed = false;

  // ── Public reads ──────────────────────────────────────────────────────────

  /// Current channel — `null` between sessions, `status: closed` after the
  /// booking ends.
  ChatChannel? get currentChannel => _channel;

  /// User id of the signed-in account driving this controller. Stable
  /// for the controller's lifetime — the auth-wired Riverpod provider
  /// reconstructs the controller on user change.
  String get selfUserId => _selfUserId;

  /// Role the local user is signed in as. UI uses (selfUserId, selfRole)
  /// as the identity tuple when deciding which side of the chat to
  /// render a bubble on. A bare userId comparison breaks on devices
  /// where the same human runs both Client + Provider apps.
  ChatSenderRole get selfRole => _selfRole;

  /// True iff the given message originated from the local user-role
  /// pair. Optimistic local sends (id `tmp_*`) are always considered
  /// "mine" by construction — the orchestrator stamps them before the
  /// server-id swap. For server-originated messages BOTH the userId
  /// AND the role have to match; without the role half, every message
  /// on a same-phone-multi-role device renders on the right side.
  bool isOwnMessage(ChatMessage m) {
    if (m.id.startsWith('tmp_')) return true;
    if (_selfUserId.isEmpty || m.senderId.isEmpty) return false;
    if (m.senderId != _selfUserId) return false;
    // Both sides must agree on role for it to count as ours. A null
    // role on the wire (legacy / unauthenticated path) falls back to
    // userId-only — same as the pre-Phase-2 behaviour.
    if (m.senderRole == null) return true;
    return m.senderRole == _selfRole;
  }

  /// Snapshot of messages, ordered by `createdAt` ascending.
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages.values);

  /// Live list of messages for the open channel. Emits a fresh snapshot on
  /// every change (history fetch, send, ack, receive, dedupe, etc.).
  Stream<List<ChatMessage>> get messagesStream => _messagesController.stream;

  /// Channel lifecycle. Emits `null` while no channel is open and a fresh
  /// [ChatChannel] each time the status flips (e.g. on close).
  Stream<ChatChannel?> get channelStream => _channelController.stream;

  /// Temp ids that are stuck in failed state. UI uses this to flip the
  /// pending-tick into a "!" retry icon.
  Stream<Set<String>> get failedIdsStream => _failedIdsController.stream;

  /// Count of received-from-other-side messages not yet locally read.
  /// Drives the unread badge on entry-point buttons.
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  /// `true` while the peer is typing in the current channel; `false`
  /// otherwise. Cleared automatically on:
  ///   - explicit `isTyping: false` from the peer
  ///   - the peer sending a message (they're done typing if they hit send)
  ///   - the orchestrator's 7 s safety net (mirrors the server's 6 s
  ///     auto-stop, plus a hop's worth of margin)
  ///   - channel close / dispose
  Stream<bool> get peerTypingStream => _peerTypingController.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Open a channel. Idempotent for the same `(bookingType, bookingId)` —
  /// re-opening the same channel re-fetches history but doesn't tear
  /// state down. Switching channels closes the previous one cleanly so
  /// messages never leak between bookings.
  Future<void> openChannel(
    ChatBookingType bookingType,
    String bookingId,
  ) async {
    if (_disposed) return;
    final isSameChannel = _channel != null &&
        _channel!.bookingType == bookingType &&
        _channel!.bookingId == bookingId;
    if (!isSameChannel) {
      await closeChannel();
    }

    _channel = ChatChannel(bookingType: bookingType, bookingId: bookingId);
    _emitChannel();

    // Subscribe BEFORE joining: we may receive messages between the join
    // ack and the history GET, and we don't want to miss them.
    _incomingSub = _realtime.incomingMessages.listen(_onIncoming);
    _readReceiptSub = _realtime.readReceipts.listen(_onReadReceipt);
    _closedSub = _realtime.channelClosed.listen(_onChannelClosed);
    _connectionSub = _realtime.connectionStream.listen(_onConnectionChange);
    _typingSub = _realtime.typingUpdates.listen(_onTypingUpdate);

    try {
      await _realtime.connect();
      await _realtime.joinChannel(bookingType, bookingId);
    } on ChatRealtimeException catch (e) {
      // The most common failure here is `CHAT_CHANNEL_CLOSED`. Surface it
      // by flipping the channel state — UI will render the locked banner.
      if (e.code == ChatErrorCodes.channelClosed) {
        _channel = _channel?.copyWith(status: ChatChannelStatus.closed);
        _emitChannel();
      }
      // Other realtime failures (network, NOT_A_PARTICIPANT) leave the
      // channel "open" so the REST history still loads — the user at
      // least sees the past thread, even if live delivery is broken.
    }

    await _hydrateHistory(bookingType, bookingId);
    await _restoreOutbox();
  }

  /// Close the current channel. Cancels stream subs, clears in-memory
  /// state, and notifies listeners. The outbox is preserved on disk so
  /// a returning user sees their unsent messages on next open.
  Future<void> closeChannel() async {
    // Politely tell the peer we're not typing anymore — server's 6 s
    // auto-stop would catch it, but flushing now hides the indicator
    // immediately on the other side.
    if (_ourTypingState) {
      _realtime.sendTyping(isTyping: false);
    }
    _resetTypingState();

    await _incomingSub?.cancel();
    await _readReceiptSub?.cancel();
    await _closedSub?.cancel();
    await _connectionSub?.cancel();
    await _typingSub?.cancel();
    _incomingSub = null;
    _readReceiptSub = null;
    _closedSub = null;
    _connectionSub = null;
    _typingSub = null;

    _realtime.leaveChannel();
    _channel = null;
    _messages.clear();
    _pendingTempIds.clear();
    _failedTempIds.clear();
    _emitAll();
  }

  /// Fully tear down. Use on logout — clears state AND the persistent
  /// outbox so the next signed-in user starts clean.
  Future<void> dispose() async {
    _disposed = true;
    final ch = _channel;
    if (ch != null) {
      await _outbox.clearChannel(_keyFor(ch));
    }
    await closeChannel();
    await _messagesController.close();
    await _channelController.close();
    await _failedIdsController.close();
    await _unreadCountController.close();
    await _peerTypingController.close();
  }

  // ── Typing ────────────────────────────────────────────────────────────────

  /// Caller signals user activity in the composer. Internally:
  ///   - First `true` after idle → emit immediately, start the 3 s idle
  ///     timer.
  ///   - Subsequent `true` while already typing → debounced; only re-emit
  ///     once the previous emit is at least 3 s old (keeps the server's
  ///     6 s auto-stop alive without spamming).
  ///   - `false` → emit immediately if we were typing, cancel the idle
  ///     timer. No-op if we weren't.
  ///
  /// Call sites: composer `onChanged` (`true`), composer focus loss
  /// (`false`), pressing send (`false`), clearing the field (`false`).
  void notifyTyping(bool isTyping) {
    if (_disposed) return;
    final channel = _channel;
    if (channel == null || channel.isClosed) return;

    if (isTyping) {
      // `clock.now()` instead of `DateTime.now()` so `fakeAsync` test
      // harnesses can advance time deterministically — the package's
      // `elapse` mocks both `Timer` and the clock, but the dart:core
      // `DateTime.now()` is not affected.
      final now = clock.now();
      final shouldEmit = !_ourTypingState ||
          (_lastTrueEmittedAt == null) ||
          now.difference(_lastTrueEmittedAt!) >= _typingDebounce;
      if (shouldEmit) {
        _realtime.sendTyping(isTyping: true);
        _lastTrueEmittedAt = now;
      }
      _ourTypingState = true;
      _localIdleTimer?.cancel();
      _localIdleTimer = Timer(_typingIdle, _onIdleAutoStop);
    } else {
      _localIdleTimer?.cancel();
      _localIdleTimer = null;
      if (_ourTypingState) {
        _realtime.sendTyping(isTyping: false);
        _ourTypingState = false;
        _lastTrueEmittedAt = null;
      }
    }
  }

  void _onIdleAutoStop() {
    if (!_ourTypingState) return;
    _realtime.sendTyping(isTyping: false);
    _ourTypingState = false;
    _lastTrueEmittedAt = null;
  }

  void _onTypingUpdate(ChatTypingUpdate update) {
    final channel = _channel;
    if (channel == null) return;
    // Channel-scope filter — the realtime layer's broadcast is room-
    // keyed already, but defensive against any cross-talk a future
    // multi-channel design might introduce.
    if (update.bookingType != channel.bookingType ||
        update.bookingId != channel.bookingId) {
      return;
    }
    // Multi-device: if the same user is signed in on two devices, the
    // backend's per-socket exclusion still lets the second device see
    // the broadcast. Filter explicitly.
    if (update.userId == _selfUserId) return;

    if (update.isTyping) {
      _typingPeerUserId = update.userId;
      _emitPeerTyping(true);
      _peerTypingClearTimer?.cancel();
      _peerTypingClearTimer = Timer(_peerTypingClearWindow, _clearPeerTyping);
    } else if (_typingPeerUserId == update.userId) {
      _clearPeerTyping();
    }
  }

  void _clearPeerTyping() {
    _peerTypingClearTimer?.cancel();
    _peerTypingClearTimer = null;
    if (_typingPeerUserId == null) return;
    _typingPeerUserId = null;
    _emitPeerTyping(false);
  }

  void _emitPeerTyping(bool typing) {
    if (_peerTypingController.isClosed) return;
    _peerTypingController.add(typing);
  }

  void _resetTypingState() {
    _localIdleTimer?.cancel();
    _localIdleTimer = null;
    _peerTypingClearTimer?.cancel();
    _peerTypingClearTimer = null;
    _ourTypingState = false;
    _lastTrueEmittedAt = null;
    if (_typingPeerUserId != null) {
      _typingPeerUserId = null;
      _emitPeerTyping(false);
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  /// Send a message in the current channel.
  ///
  /// Optimistic-appends a `tmp_…` bubble, persists to outbox, then races
  /// the socket emit against a REST POST. Whichever wins replaces the
  /// temp id with the server id and removes the outbox item. If both
  /// fail, the bubble stays put with `failed: true` and the user can
  /// tap [retry].
  Future<ChatMessage?> send(String text) async {
    final channel = _channel;
    if (channel == null) {
      throw StateError('No channel open — call openChannel first.');
    }
    if (channel.isClosed) {
      throw const ApiException(
        message: 'This chat is closed.',
        errorCode: ChatErrorCodes.channelClosed,
      );
    }
    final body = text.trim();
    if (body.isEmpty) return null;

    final tempId = _generateTempId();
    final optimistic = ChatMessage(
      id: tempId,
      senderId: _selfUserId,
      senderRole: _selfRole,
      message: body,
      createdAt: DateTime.now().toUtc(),
    );
    _messages[tempId] = optimistic;
    _pendingTempIds.add(tempId);
    _emitMessages();

    final item = ChatOutboxItem(
      tempId: tempId,
      channelKey: _keyFor(channel),
      message: body,
      queuedAt: optimistic.createdAt,
    );
    await _outbox.upsert(item);

    return _attemptSend(item);
  }

  /// Retry a failed message. Bumps `attemptCount` and re-fires the same
  /// race (socket → REST). No-op if [tempId] isn't a known failed item.
  Future<ChatMessage?> retry(String tempId) async {
    final existing = _messages[tempId];
    if (existing == null || !_failedTempIds.contains(tempId)) return null;
    final channel = _channel;
    if (channel == null) return null;

    final updated = ChatOutboxItem(
      tempId: tempId,
      channelKey: _keyFor(channel),
      message: existing.message,
      queuedAt: existing.createdAt,
      attemptCount: 0, // reset for the manual retry
    ).copyWith(attemptCount: 1);
    await _outbox.upsert(updated);

    _failedTempIds.remove(tempId);
    _pendingTempIds.add(tempId);
    _emitFailed();
    return _attemptSend(updated);
  }

  /// Race the socket against REST. Whichever lands first wins; the loser
  /// is ignored. Returns the persisted [ChatMessage] on success or `null`
  /// if both failed.
  Future<ChatMessage?> _attemptSend(ChatOutboxItem item) async {
    final channel = _channel;
    if (channel == null) return null;

    try {
      // Socket first — it's lower-latency and the spec's primary path.
      // Only fall through to REST when the realtime layer says it
      // couldn't deliver (timeout / not connected / unknown ack shape).
      final saved = await _realtime.sendMessage(message: item.message);
      _commitSent(item.tempId, saved);
      return saved;
    } on ChatRealtimeException catch (e) {
      // Channel-closed or similar terminal failure — surface and stop.
      if (e.code == ChatErrorCodes.channelClosed) {
        _markFailed(item);
        _channel = _channel?.copyWith(status: ChatChannelStatus.closed);
        _emitChannel();
        return null;
      }
      // For ackTimeout / notConnected / unknown — try REST.
      try {
        final saved = await _rest.sendMessage(
          channel.bookingType,
          channel.bookingId,
          message: item.message,
        );
        _commitSent(item.tempId, saved);
        return saved;
      } on ApiException catch (apiErr) {
        if (apiErr.errorCode == ChatErrorCodes.channelClosed) {
          _markFailed(item);
          _channel = _channel?.copyWith(status: ChatChannelStatus.closed);
          _emitChannel();
          return null;
        }
        _markFailed(item);
        return null;
      } catch (_) {
        _markFailed(item);
        return null;
      }
    } catch (_) {
      // Any non-Realtime exception (e.g. socket library blew up): try REST.
      try {
        final saved = await _rest.sendMessage(
          channel.bookingType,
          channel.bookingId,
          message: item.message,
        );
        _commitSent(item.tempId, saved);
        return saved;
      } catch (_) {
        _markFailed(item);
        return null;
      }
    }
  }

  void _commitSent(String tempId, ChatMessage saved) {
    // Replace the optimistic entry with the real one, preserving the
    // insertion order so the bubble doesn't jump.
    final reordered = <String, ChatMessage>{};
    for (final entry in _messages.entries) {
      if (entry.key == tempId) {
        reordered[saved.id] = saved;
      } else {
        reordered[entry.key] = entry.value;
      }
    }
    _messages
      ..clear()
      ..addAll(reordered);
    _pendingTempIds.remove(tempId);
    _failedTempIds.remove(tempId);
    _outbox.remove(tempId);
    _emitMessages();
    _emitFailed();
  }

  void _markFailed(ChatOutboxItem item) {
    _pendingTempIds.remove(item.tempId);
    _failedTempIds.add(item.tempId);
    // Bump attempt count so the UI can stop offering auto-retry after N
    // tries (5 is a sensible cap; UI policy lives outside this class).
    _outbox.upsert(item.copyWith(attemptCount: item.attemptCount + 1));
    _emitFailed();
  }

  // ── Read receipts ─────────────────────────────────────────────────────────

  /// Mark a message as read. Skips own messages and already-read ones.
  /// Idempotent — safe to call from a VisibilityDetector callback.
  Future<void> markRead(String messageId) async {
    if (messageId.startsWith('tmp_')) return;
    final m = _messages[messageId];
    if (m == null) return;
    if (isOwnMessage(m)) return; // can't read own
    if (m.isRead) return;

    DateTime? readAt;
    try {
      readAt = await _realtime.markRead(messageId: messageId);
    } on ChatRealtimeException catch (e) {
      if (e.code == ChatErrorCodes.ackTimeout ||
          e.code == ChatErrorCodes.notConnected) {
        try {
          readAt = await _rest.markRead(messageId);
        } catch (_) {
          // Swallow — the next visibility tick will retry. The recipient
          // doesn't see a UI consequence either way.
        }
      }
    } catch (_) {
      // Same swallow as above for non-typed exceptions.
    }
    if (readAt == null) return;
    _messages[messageId] = m.copyWith(readAt: readAt);
    _emitMessages();
  }

  // ── Inbound handlers ──────────────────────────────────────────────────────

  void _onIncoming(ChatMessage incoming) {
    // Only relevant to the active channel — realtime broadcasts every
    // room we've joined, but we should only have one room joined at a
    // time. Defensive check anyway.
    final channel = _channel;
    if (channel == null) return;

    // De-dupe by id. The backend echoes the sender's own message back via
    // the room broadcast; if we already committed it from the send ack,
    // skip. If we still have it as a tmp_ id (the broadcast beat the
    // ack), swap.
    if (_messages.containsKey(incoming.id)) return;

    // Try to match an optimistic temp by sender+text — only the sender
    // has a tmp entry, so this only matters for our own broadcasts.
    // Role-aware: on a same-phone-multi-role device the peer can share
    // our userId, so we'd otherwise swallow their messages into our
    // pending tmp slot. `isOwnMessage` checks both (userId, role).
    if (isOwnMessage(incoming)) {
      final tmp = _messages.entries
          .where(
            (e) =>
                e.key.startsWith('tmp_') &&
                isOwnMessage(e.value) &&
                e.value.message == incoming.message,
          )
          .firstOrNull;
      if (tmp != null) {
        _commitSent(tmp.key, incoming);
        return;
      }
    }

    _messages[incoming.id] = incoming;
    // Peer sending a message means they're done typing — clear the
    // indicator now even if the corresponding `isTyping: false` event
    // hasn't arrived yet.
    if (_typingPeerUserId == incoming.senderId) {
      _clearPeerTyping();
    }
    _emitMessages();
    _emitUnreadCount();
  }

  void _onReadReceipt(ChatReadReceipt receipt) {
    final m = _messages[receipt.messageId];
    if (m == null) return;
    _messages[receipt.messageId] = m.copyWith(readAt: receipt.readAt);
    _emitMessages();
  }

  void _onChannelClosed(ChatChannelClosedEvent evt) {
    final ch = _channel;
    if (ch == null) return;
    if (ch.bookingType != evt.bookingType || ch.bookingId != evt.bookingId) {
      return;
    }
    _channel = ch.copyWith(status: ChatChannelStatus.closed);
    _emitChannel();
    // Outbox items targeting a closed channel will only ever fail with
    // CHAT_CHANNEL_CLOSED — drop them so the user doesn't keep retrying
    // a doomed send.
    _outbox.clearChannel(_keyFor(ch));
  }

  /// On reconnect (false → true while a channel is active) re-fetch the
  /// REST history and merge to backfill any messages we missed during
  /// the disconnect window. Dedupe by id.
  void _onConnectionChange(bool connected) {
    if (!connected) return;
    final channel = _channel;
    if (channel == null) return;
    unawaited(_hydrateHistory(channel.bookingType, channel.bookingId));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _hydrateHistory(
    ChatBookingType bookingType,
    String bookingId,
  ) async {
    try {
      final history = await _rest.getMessages(bookingType, bookingId);
      // Merge: server rows are authoritative for any id they cover; our
      // tmp_ optimistic rows remain in place.
      final preservedTemps = <MapEntry<String, ChatMessage>>[
        for (final e in _messages.entries)
          if (e.key.startsWith('tmp_')) e,
      ];
      _messages.clear();
      for (final m in history) {
        _messages[m.id] = m;
      }
      // Re-insert tmps so the chronological order reflects when the user
      // typed them, not their (absent) server timestamp.
      for (final e in preservedTemps) {
        _messages[e.key] = e.value;
      }
      _emitMessages();
      _emitUnreadCount();
    } catch (_) {
      // Phase 4 surfaces a "couldn't load history" banner. For now the
      // last good list stays put.
    }
  }

  Future<void> _restoreOutbox() async {
    final channel = _channel;
    if (channel == null) return;
    final items = await _outbox.readForChannel(_keyFor(channel));
    var changed = false;
    for (final item in items) {
      // Skip if a real message with the same body already exists — covers
      // the rare case where we crashed after the server saved but before
      // we removed the outbox item.
      final dupeFound = _messages.values.any(
        (m) =>
            isOwnMessage(m) &&
            m.message == item.message &&
            (m.createdAt.difference(item.queuedAt)).abs() <
                const Duration(minutes: 1),
      );
      if (dupeFound) {
        await _outbox.remove(item.tempId);
        continue;
      }
      _messages[item.tempId] = ChatMessage(
        id: item.tempId,
        senderId: _selfUserId,
        senderRole: _selfRole,
        message: item.message,
        createdAt: item.queuedAt,
      );
      _failedTempIds.add(item.tempId);
      changed = true;
    }
    if (changed) {
      _emitMessages();
      _emitFailed();
    }
  }

  String _generateTempId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final tail = _random.nextInt(0xFFFFFFFF).toRadixString(36);
    return 'tmp_${ts}_$tail';
  }

  String _keyFor(ChatChannel c) =>
      chatChannelKey(c.bookingType.wire, c.bookingId);

  // ── Emit helpers ──────────────────────────────────────────────────────────

  void _emitAll() {
    _emitMessages();
    _emitChannel();
    _emitFailed();
    _emitUnreadCount();
  }

  void _emitMessages() {
    if (_messagesController.isClosed) return;
    _messagesController.add(currentMessages);
    _emitUnreadCount();
  }

  void _emitChannel() {
    if (_channelController.isClosed) return;
    _channelController.add(_channel);
  }

  void _emitFailed() {
    if (_failedIdsController.isClosed) return;
    _failedIdsController.add(Set<String>.from(_failedTempIds));
  }

  void _emitUnreadCount() {
    if (_unreadCountController.isClosed) return;
    // Role-aware: on same-phone-multi-role devices, "from peer" can't
    // be derived from `senderId != _selfUserId` alone — the userId
    // collides. `isOwnMessage` checks (userId, role) together.
    final count =
        _messages.values.where((m) => !isOwnMessage(m) && !m.isRead).length;
    _unreadCountController.add(count);
  }
}

/// Treats the iterable's first element as nullable.
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
