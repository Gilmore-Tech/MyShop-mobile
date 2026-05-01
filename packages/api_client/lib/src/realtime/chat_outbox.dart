import 'dart:async';

/// A pending outgoing message that hasn't been acknowledged by the server.
///
/// The orchestrator inserts an item the moment the user taps Send, so the
/// optimistic bubble has a stable identity ([tempId]) before any network
/// round-trip. The item is removed on success and left on the queue (with
/// [attemptCount] bumped) on every failure, so a retry tap re-uses the
/// same record and the bubble's id never flips mid-thread.
///
/// Stored on disk by the app-specific [ChatOutbox] implementation so a
/// failed send survives an app kill / device reboot.
class ChatOutboxItem {
  const ChatOutboxItem({
    required this.tempId,
    required this.channelKey,
    required this.message,
    required this.queuedAt,
    this.attemptCount = 0,
  });

  factory ChatOutboxItem.fromJson(Map<String, dynamic> json) {
    return ChatOutboxItem(
      tempId: json['tempId'] as String,
      channelKey: json['channelKey'] as String,
      message: json['message'] as String,
      queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Locally-assigned id (`tmp_<microseconds>_<rand>`). The bubble's
  /// stable identity until the server-side id arrives via send ack.
  final String tempId;

  /// Channel scope — `'${bookingType.wire}:${bookingId}'`. Lets storage
  /// cheaply slice the queue per channel without parsing values.
  final String channelKey;

  final String message;
  final DateTime queuedAt;

  /// Number of failed attempts. Used by the UI to decide when to stop
  /// auto-retrying (e.g. on socket reconnect) and surface a manual retry.
  final int attemptCount;

  ChatOutboxItem copyWith({int? attemptCount}) {
    return ChatOutboxItem(
      tempId: tempId,
      channelKey: channelKey,
      message: message,
      queuedAt: queuedAt,
      attemptCount: attemptCount ?? this.attemptCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'tempId': tempId,
        'channelKey': channelKey,
        'message': message,
        'queuedAt': queuedAt.toUtc().toIso8601String(),
        'attemptCount': attemptCount,
      };
}

/// Storage contract for the chat outbox. Apps provide a disk-backed
/// implementation (see `SharedPreferencesChatOutbox` in each app).
///
/// All operations are async because disk-backed implementations can't
/// block; in-memory tests are still legal — they just complete
/// synchronously.
abstract class ChatOutbox {
  /// Items queued for [channelKey], ordered by [ChatOutboxItem.queuedAt].
  Future<List<ChatOutboxItem>> readForChannel(String channelKey);

  /// Persist a new item. If [item.tempId] already exists, replaces it
  /// (covers the "user retried while another retry was already in flight"
  /// race).
  Future<void> upsert(ChatOutboxItem item);

  /// Remove an item by its local temp id. No-op if not found.
  Future<void> remove(String tempId);

  /// Drop every item belonging to [channelKey]. Called when the channel
  /// closes — outbox items targeting a closed channel will only ever
  /// fail with `CHAT_CHANNEL_CLOSED`, no point keeping them.
  Future<void> clearChannel(String channelKey);
}

/// Process-local outbox. Useful for tests and as a fallback when the
/// app hasn't wired a disk-backed implementation yet. Survives nothing
/// past process shutdown.
class InMemoryChatOutbox implements ChatOutbox {
  final Map<String, ChatOutboxItem> _items = <String, ChatOutboxItem>{};

  @override
  Future<List<ChatOutboxItem>> readForChannel(String channelKey) async {
    final hits = _items.values
        .where((i) => i.channelKey == channelKey)
        .toList(growable: false);
    hits.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return hits;
  }

  @override
  Future<void> upsert(ChatOutboxItem item) async {
    _items[item.tempId] = item;
  }

  @override
  Future<void> remove(String tempId) async {
    _items.remove(tempId);
  }

  @override
  Future<void> clearChannel(String channelKey) async {
    _items.removeWhere((_, item) => item.channelKey == channelKey);
  }
}

/// `'${bookingType.wire}:${bookingId}'` — the outbox key the controller
/// uses everywhere. Re-exported as a top-level helper so the
/// app-specific disk impls can build the same key without depending on
/// the controller.
String chatChannelKey(String bookingTypeWire, String bookingId) {
  return '$bookingTypeWire:$bookingId';
}
