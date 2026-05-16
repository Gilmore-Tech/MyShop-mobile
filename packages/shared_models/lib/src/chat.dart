/// Chat models matching the backend contract.
///
///   - REST: GET/POST `/chat/:bookingType/:bookingId/messages`,
///           PATCH `/chat/messages/:messageId/read`
///   - WS namespace `/chat`, room keyed by `(bookingType, bookingId)`
///
/// `bookingType` on the wire is `'ride'` or `'artisan_job'` (not `'job'` —
/// the older endpoints used a different convention).

/// Booking surface a chat is attached to.
enum ChatBookingType {
  ride('ride'),
  artisanJob('artisan_job');

  const ChatBookingType(this.wire);

  /// String the backend expects in URLs and socket payloads.
  final String wire;

  static ChatBookingType? fromWire(String? raw) {
    switch (raw) {
      case 'ride':
        return ChatBookingType.ride;
      case 'artisan_job':
      // Tolerate the older `'job'` spelling some legacy paths still use,
      // so a stale notification or stored route doesn't drop into the
      // "couldn't parse" path silently.
      case 'job':
        return ChatBookingType.artisanJob;
    }
    return null;
  }
}

/// Lifecycle of a chat channel.
///
/// `closed` is sticky for the booking — once the backend emits
/// `chat:channel:closed` (booking transitioned to completed/cancelled) we
/// keep the channel readable but lock the composer.
enum ChatChannelStatus { open, closed }

/// Role the sender of a chat message had on the booking. Used to render
/// "Kofi (Driver)" / "Abena (Client)" style labels in the chat bubble so
/// a multi-role user (one phone holding Client + Driver + Artisan) can
/// tell which side of the booking they were on when they sent it.
enum ChatSenderRole {
  client('client', 'Client'),
  driver('driver', 'Driver'),
  artisan('artisan', 'Artisan');

  const ChatSenderRole(this.wire, this.label);

  final String wire;
  final String label;

  static ChatSenderRole? fromWire(String? raw) {
    switch (raw) {
      case 'client':
        return ChatSenderRole.client;
      case 'driver':
        return ChatSenderRole.driver;
      case 'artisan':
        return ChatSenderRole.artisan;
    }
    return null;
  }
}

/// A single chat message — both REST `messages[]` rows and `chat:message:*`
/// socket payloads land here.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.message,
    required this.createdAt,
    this.senderRole,
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Tolerate the backend emitting `senderId` (camelCase, current spec),
    // `sender_id` (snake_case, common Postgres-driven payloads), or
    // `userId` (a few legacy paths) — any divergence here was the
    // smoking gun behind every bubble rendering as `fromMe` because
    // the parser fell back to `''` and matched an equally-empty selfId.
    final sender = (json['senderId'] ??
            json['sender_id'] ??
            json['userId'] ??
            json['user_id']) as String? ??
        '';
    return ChatMessage(
      id: json['id'] as String,
      senderId: sender,
      senderRole: ChatSenderRole.fromWire(
        (json['senderRole'] ?? json['sender_role']) as String?,
      ),
      message: json['message'] as String? ?? json['content'] as String? ?? '',
      readAt: _parseDate(json['readAt']),
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now().toUtc(),
    );
  }

  /// Backend message id (UUID). Mobile assigns a temporary `tmp_…` id while
  /// optimistically rendering — callers should swap once the ack lands so
  /// dedupe keys stay stable.
  final String id;

  /// User id of the sender. The recipient is implicit (the other party on
  /// the booking) — the backend addresses it by participant lookup.
  final String senderId;

  /// Role the sender held on this booking. Null on optimistic mobile-side
  /// rows (we don't know our own role at that layer); the server ack will
  /// fill it in on the way back. Used to render "Kofi (Driver)" labels
  /// when a multi-role user needs to disambiguate which side sent.
  final ChatSenderRole? senderRole;

  /// Body. 1–2000 chars, UTF-8. The backend trims and validates length;
  /// the composer should mirror that cap.
  final String message;

  /// When the recipient read this message. Null while undelivered/unread.
  final DateTime? readAt;

  /// Server-assigned creation timestamp (UTC). Used for ordering and
  /// for the "MM:HH" stamp in the message bubble.
  final DateTime createdAt;

  bool get isRead => readAt != null;

  ChatMessage copyWith({
    String? id,
    String? senderId,
    ChatSenderRole? senderRole,
    String? message,
    DateTime? readAt,
    DateTime? createdAt,
    bool clearReadAt = false,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      message: message ?? this.message,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Identifier + lifecycle for a chat channel.
///
/// Two channels on the same booking are equal by `(bookingType, bookingId)`;
/// the [status] flips after `chat:channel:closed`.
class ChatChannel {
  const ChatChannel({
    required this.bookingType,
    required this.bookingId,
    this.status = ChatChannelStatus.open,
  });

  final ChatBookingType bookingType;
  final String bookingId;
  final ChatChannelStatus status;

  bool get isOpen => status == ChatChannelStatus.open;
  bool get isClosed => status == ChatChannelStatus.closed;

  ChatChannel copyWith({ChatChannelStatus? status}) {
    return ChatChannel(
      bookingType: bookingType,
      bookingId: bookingId,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatChannel &&
          other.bookingType == bookingType &&
          other.bookingId == bookingId &&
          other.status == status);

  @override
  int get hashCode => Object.hash(bookingType, bookingId, status);
}

/// Backend error codes for chat REST + socket. Keeping them as plain
/// constants so callers can switch on them without pulling in an enum
/// dependency from the api_client side.
class ChatErrorCodes {
  const ChatErrorCodes._();

  static const notAParticipant = 'NOT_A_PARTICIPANT';
  static const bookingNotFound = 'BOOKING_NOT_FOUND';
  static const messageNotFound = 'MESSAGE_NOT_FOUND';
  static const cannotReadOwnMessage = 'CANNOT_READ_OWN_MESSAGE';
  static const channelClosed = 'CHAT_CHANNEL_CLOSED';
  static const messageEmpty = 'MESSAGE_EMPTY';
  static const messageTooLong = 'MESSAGE_TOO_LONG';

  /// Surfaced by the realtime layer when the server's ack carries a
  /// non-2xx envelope or no envelope at all.
  static const unknown = 'CHAT_UNKNOWN_ERROR';

  /// Local-only — the socket couldn't deliver the emit within the ack
  /// timeout. Triggers the REST fallback in the orchestrator.
  static const ackTimeout = 'CHAT_ACK_TIMEOUT';

  /// Local-only — emit attempted while the socket was not connected.
  static const notConnected = 'CHAT_NOT_CONNECTED';
}

/// Payload of `chat:read:receipt` — the other party has read one of our
/// messages.
class ChatReadReceipt {
  const ChatReadReceipt({
    required this.messageId,
    required this.readAt,
    required this.readBy,
  });

  factory ChatReadReceipt.fromJson(Map<String, dynamic> json) {
    return ChatReadReceipt(
      messageId: json['messageId'] as String,
      readAt: _parseDate(json['readAt']) ?? DateTime.now().toUtc(),
      readBy: json['readBy'] as String? ?? '',
    );
  }

  final String messageId;
  final DateTime readAt;

  /// User id of the reader. Used for multi-device dedupe — one of the
  /// reader's devices flips first, the others get notified via this event
  /// and skip re-emitting.
  final String readBy;
}

/// Payload of `chat:typing:update` — the other party started or stopped
/// typing in the room.
///
/// Backend behaviour:
///   - Sender excluded from the broadcast (so multi-device doesn't echo
///     a user typing on one device to themselves on another).
///   - Server-side auto-stop after 6 s of no further `isTyping: true`
///     from the same sender — so the recipient never gets stuck on
///     "typing…" if a client crashes mid-keystroke.
///   - Disconnect handler emits a final `isTyping: false` to every room
///     the user was typing in.
class ChatTypingUpdate {
  const ChatTypingUpdate({
    required this.bookingType,
    required this.bookingId,
    required this.userId,
    required this.isTyping,
  });

  factory ChatTypingUpdate.fromJson(Map<String, dynamic> json) {
    return ChatTypingUpdate(
      bookingType: ChatBookingType.fromWire(json['bookingType'] as String?) ??
          ChatBookingType.ride,
      bookingId: json['bookingId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      isTyping: json['isTyping'] as bool? ?? false,
    );
  }

  final ChatBookingType bookingType;
  final String bookingId;

  /// User id of the typist. Mobile filters out updates where this matches
  /// the local user (multi-device defensive — the backend already excludes
  /// the sending socket but a second device on the same account would
  /// still receive the broadcast).
  final String userId;

  final bool isTyping;
}

/// Payload of `chat:channel:closed` — booking transitioned to
/// completed/cancelled, the channel is now read-only.
class ChatChannelClosedEvent {
  const ChatChannelClosedEvent({
    required this.bookingType,
    required this.bookingId,
    required this.reason,
  });

  factory ChatChannelClosedEvent.fromJson(Map<String, dynamic> json) {
    return ChatChannelClosedEvent(
      bookingType: ChatBookingType.fromWire(json['bookingType'] as String?) ??
          ChatBookingType.ride,
      bookingId: json['bookingId'] as String? ?? '',
      reason: json['reason'] as String? ?? 'closed',
    );
  }

  final ChatBookingType bookingType;
  final String bookingId;

  /// Human-readable reason from the backend (e.g. `'completed'`,
  /// `'cancelled'`). Surfaced to the closed-channel banner.
  final String reason;
}

DateTime? _parseDate(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
