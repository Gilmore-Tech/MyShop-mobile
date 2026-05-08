/// Support ticket models matching the backend contract.
///
///   - REST: `/v1/support/tickets`, `/v1/support/tickets/:id/messages`
///   - FCM: `support_ticket_message`, `support_ticket_status_changed`
///
/// Tickets are reachable from both apps (client + provider). The set of
/// allowed [TicketCategory] values differs per audience but the model is
/// the same — the backend stores the wire string and the UI filters the
/// dropdown based on [SupportAudience].

/// Audience the ticket is filed under. The backend uses this to filter
/// help articles + legal documents per app and to scope category enums.
///
/// `driver` and `artisan` are legal-only at present — they let the backend
/// serve role-specific Terms / policies in the provider app, while help
/// articles and tickets continue to use `provider`. The legal service falls
/// back driver→provider→both and artisan→provider→both when no role-specific
/// version is published.
enum SupportAudience {
  client('client'),
  provider('provider'),
  driver('driver'),
  artisan('artisan');

  const SupportAudience(this.wire);

  final String wire;

  static SupportAudience? fromWire(String? raw) {
    switch (raw) {
      case 'client':
        return SupportAudience.client;
      case 'provider':
        return SupportAudience.provider;
      case 'driver':
        return SupportAudience.driver;
      case 'artisan':
        return SupportAudience.artisan;
    }
    return null;
  }
}

/// Lifecycle of a support ticket.
///
///   - [open]: filed, no agent has picked it up yet
///   - [inProgress]: an agent is working on it
///   - [waitingUser]: agent has replied and is waiting on the user
///   - [resolved]: closed by user or agent — re-openable for 7 days
///   - [closed]: terminal — re-opening creates a new ticket
enum TicketStatus {
  open('open'),
  inProgress('in_progress'),
  waitingUser('waiting_user'),
  resolved('resolved'),
  closed('closed');

  const TicketStatus(this.wire);

  final String wire;

  static TicketStatus fromWire(String? raw) {
    for (final s in TicketStatus.values) {
      if (s.wire == raw) return s;
    }
    return TicketStatus.open;
  }

  bool get isTerminal => this == TicketStatus.closed;
  bool get isReopenable => this == TicketStatus.resolved;
  bool get isAwaitingUser => this == TicketStatus.waitingUser;
}

/// Topical bucket assigned at filing. The dropdown is filtered by audience
/// — see [clientCategories] / [providerCategories].
enum TicketCategory {
  account('account'),
  payments('payments'),
  rides('rides'),
  jobs('jobs'),
  payouts('payouts'),
  verification('verification'),
  safety('safety'),
  bug('bug'),
  other('other');

  const TicketCategory(this.wire);

  final String wire;

  static TicketCategory fromWire(String? raw) {
    for (final c in TicketCategory.values) {
      if (c.wire == raw) return c;
    }
    return TicketCategory.other;
  }

  static const List<TicketCategory> clientCategories = [
    TicketCategory.account,
    TicketCategory.payments,
    TicketCategory.rides,
    TicketCategory.jobs,
    TicketCategory.safety,
    TicketCategory.bug,
    TicketCategory.other,
  ];

  static const List<TicketCategory> providerCategories = [
    TicketCategory.account,
    TicketCategory.payouts,
    TicketCategory.jobs,
    TicketCategory.verification,
    TicketCategory.safety,
    TicketCategory.bug,
    TicketCategory.other,
  ];
}

/// Caller-suggested priority — the backend may override (e.g. safety
/// reports get auto-bumped).
enum TicketPriority {
  low('low'),
  normal('normal'),
  high('high'),
  urgent('urgent');

  const TicketPriority(this.wire);

  final String wire;

  static TicketPriority fromWire(String? raw) {
    for (final p in TicketPriority.values) {
      if (p.wire == raw) return p;
    }
    return TicketPriority.normal;
  }
}

/// Who authored a [TicketMessage]. Used by the chat-style UI to flip
/// `fromMe` and pick the bubble colour.
///
///   - [user]: the ticket owner (current logged-in user)
///   - [agent]: a support agent
///   - [system]: an automated note (status flips, escalations)
enum TicketSenderRole {
  user('user'),
  agent('agent'),
  system('system');

  const TicketSenderRole(this.wire);

  final String wire;

  static TicketSenderRole fromWire(String? raw) {
    switch (raw) {
      case 'user':
        return TicketSenderRole.user;
      case 'agent':
      case 'support':
        return TicketSenderRole.agent;
      case 'system':
        return TicketSenderRole.system;
    }
    return TicketSenderRole.user;
  }
}

/// File attached to a ticket or a ticket message.
///
/// Uploads go through the `POST /v1/support/uploads/sign` presigned-URL
/// flow first — the mobile uploads to S3 directly, then sends just the
/// resulting public/signed [url] back when filing the ticket / message.
class TicketAttachment {
  const TicketAttachment({
    required this.url,
    required this.mime,
    required this.sizeBytes,
    this.filename,
  });

  factory TicketAttachment.fromJson(Map<String, dynamic> json) {
    return TicketAttachment(
      url: json['url'] as String? ?? '',
      mime: json['mime'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      filename: json['filename'] as String?,
    );
  }

  final String url;
  final String mime;
  final int sizeBytes;
  final String? filename;

  Map<String, dynamic> toJson() => {
        'url': url,
        'mime': mime,
        'sizeBytes': sizeBytes,
        if (filename != null) 'filename': filename,
      };

  bool get isImage => mime.startsWith('image/');
}

/// A single message on a ticket — first user message + every reply.
class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.ticketId,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.attachments = const [],
    this.readAt,
  });

  factory TicketMessage.fromJson(Map<String, dynamic> json) {
    return TicketMessage(
      id: json['id'] as String? ?? '',
      ticketId: json['ticketId'] as String? ?? '',
      senderRole: TicketSenderRole.fromWire(json['senderRole'] as String?),
      senderId: json['senderId'] as String?,
      body: json['body'] as String? ?? '',
      attachments: (json['attachments'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(TicketAttachment.fromJson)
              .toList(growable: false) ??
          const [],
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now().toUtc(),
      readAt: _parseDate(json['readAt']),
    );
  }

  final String id;
  final String ticketId;
  final TicketSenderRole senderRole;
  final String? senderId;
  final String body;
  final List<TicketAttachment> attachments;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isFromUser => senderRole == TicketSenderRole.user;
  bool get isFromAgent => senderRole == TicketSenderRole.agent;
  bool get isSystemNote => senderRole == TicketSenderRole.system;
}

/// A support ticket — list rows and the detail header both decode here.
///
/// On the list endpoint, [lastMessagePreview] / [unreadCount] are populated;
/// detailed message bodies live on [TicketMessage] fetched separately.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.category,
    required this.subject,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.referenceType,
    this.referenceId,
    this.attachments = const [],
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: json['id'] as String? ?? json['ticketId'] as String? ?? '',
      category: TicketCategory.fromWire(json['category'] as String?),
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String?,
      status: TicketStatus.fromWire(json['status'] as String?),
      priority: TicketPriority.fromWire(json['priority'] as String?),
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now().toUtc(),
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now().toUtc(),
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt: _parseDate(json['lastMessageAt']),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      referenceType: json['referenceType'] as String?,
      referenceId: json['referenceId'] as String?,
      attachments: (json['attachments'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(TicketAttachment.fromJson)
              .toList(growable: false) ??
          const [],
    );
  }

  final String id;
  final TicketCategory category;
  final String subject;
  final String? description;
  final TicketStatus status;
  final TicketPriority priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;

  /// Unread agent/system messages on this ticket. Drives the badge dot.
  final int unreadCount;

  /// Optional pointer to the underlying record this ticket is about.
  /// `'ride' | 'job' | 'payout' | 'bid' | 'payment' | …` — the agent
  /// console uses this to jump into the related item.
  final String? referenceType;
  final String? referenceId;

  /// Attachments uploaded with the original filing. Reply attachments
  /// hang off [TicketMessage] instead.
  final List<TicketAttachment> attachments;

  bool get hasUnread => unreadCount > 0;
  bool get isOpen => !status.isTerminal;

  SupportTicket copyWith({
    TicketStatus? status,
    TicketPriority? priority,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? updatedAt,
  }) {
    return SupportTicket(
      id: id,
      category: category,
      subject: subject,
      description: description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      referenceType: referenceType,
      referenceId: referenceId,
      attachments: attachments,
    );
  }
}

/// Cursor-paginated result for `GET /v1/support/tickets` and
/// `/v1/support/tickets/:id/messages`. The mobile pages forward only —
/// older messages load as the user scrolls back.
class TicketPage<T> {
  const TicketPage({required this.items, this.nextCursor});

  factory TicketPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) decode,
  ) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return TicketPage(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(decode)
          .toList(growable: false),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

DateTime? _parseDate(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
