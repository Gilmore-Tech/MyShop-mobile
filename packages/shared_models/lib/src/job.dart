/// Server-authored phase for a directed admin assignment.
enum JobAssignmentPhase {
  awaitingQuote,
  awaitingAdminReview,
  awaitingClientAccept;

  static JobAssignmentPhase? fromString(String? value) => switch (value) {
        'awaiting_quote' => JobAssignmentPhase.awaitingQuote,
        'awaiting_admin_review' => JobAssignmentPhase.awaitingAdminReview,
        'awaiting_client_accept' => JobAssignmentPhase.awaitingClientAccept,
        _ => null,
      };
}

/// Additive assignment envelope returned by newer backend versions.
///
/// All fields remain nullable so older app builds and legacy records continue
/// to parse even when the envelope is absent or partially populated.
class JobAssignment {
  const JobAssignment({
    this.attemptId,
    this.revision,
    this.phase,
    this.quoteDeadlineAt,
    this.acceptDeadlineAt,
  });

  factory JobAssignment.fromJson(Map<String, dynamic> json) => JobAssignment(
        attemptId: json['attemptId'] as String?,
        revision: (json['revision'] as num?)?.toInt(),
        phase: JobAssignmentPhase.fromString(json['phase'] as String?),
        quoteDeadlineAt: json['quoteDeadlineAt'] as String?,
        acceptDeadlineAt: json['acceptDeadlineAt'] as String?,
      );

  final String? attemptId;
  final int? revision;
  final JobAssignmentPhase? phase;
  final String? quoteDeadlineAt;
  final String? acceptDeadlineAt;

  DateTime? get quoteDeadline =>
      quoteDeadlineAt == null ? null : DateTime.tryParse(quoteDeadlineAt!);
  DateTime? get acceptDeadline =>
      acceptDeadlineAt == null ? null : DateTime.tryParse(acceptDeadlineAt!);
}

/// A service job request created by a client for an artisan.
///
/// Standard status flow:
///   open → confirmed → artisan_en_route → arrived →
///   in_progress → artisan_marked_complete → completed
///
/// Admin-assignment fallback (when no artisans bid in the window):
///   open → (bid window expires) → pending_admin → admin_assigned →
///   (artisan quotes) → confirmed → ... → completed
///
/// (can be cancelled at most stages)
class Job {
  const Job({
    required this.id,
    required this.status,
    required this.categoryId,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.categoryName,
    this.addressText,
    this.photos = const [],
    this.scheduledFor,
    this.clientName,
    this.clientPhone,
    this.clientPhotoUrl,
    this.agreedPricePesewas,
    this.shareToken,
    this.artisansNotified,
    this.createdAt,
    this.expiresAt,
    this.assignedArtisanId,
    this.assignedByAdmin,
    this.assignedAt,
    this.assignment,
    this.startedAt,
    this.completedAt,
    this.clientPaymentAcknowledgedAt,
    this.clientPaymentMethod,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    // The backend sometimes flattens client fields at the top level and
    // sometimes nests them under `client: {...}` (matching the convention
    // used for artisan/provider payloads elsewhere). Support both so the
    // artisan-side UI renders real names/phones regardless of which
    // endpoint served the record.
    final clientMap = json['client'] as Map<String, dynamic>?;

    String? resolvedClientName = json['clientName'] as String?;
    if ((resolvedClientName == null || resolvedClientName.isEmpty) &&
        clientMap != null) {
      final full = (clientMap['fullName'] ?? clientMap['name']) as String?;
      if (full != null && full.trim().isNotEmpty) {
        resolvedClientName = full.trim();
      } else {
        final first = clientMap['firstName'] as String? ?? '';
        final last = clientMap['lastName'] as String? ?? '';
        final joined = '$first $last'.trim();
        if (joined.isNotEmpty) resolvedClientName = joined;
      }
    }

    final resolvedClientPhone = json['clientPhone'] as String? ??
        clientMap?['phone'] as String? ??
        clientMap?['maskedPhone'] as String?;

    final resolvedClientPhotoUrl = json['clientPhotoUrl'] as String? ??
        clientMap?['profilePhotoUrl'] as String? ??
        clientMap?['photoUrl'] as String?;

    // Diagnostic — when the parser can't find any client identity, dump
    // the top-level keys + the nested `client` keys (if present) so we
    // can tell whether the backend simply isn't sending the data, or is
    // sending it under a key we don't yet handle. Filter `printOnDebug`
    // by your IDE if it gets noisy; remove once the artisan flow is
    // confirmed showing real names end-to-end.
    if (resolvedClientName == null && resolvedClientPhotoUrl == null) {
      // ignore: avoid_print
      print(
        '[Job.fromJson] No client identity for jobId=${json['id'] ?? json['jobId']} '
        'topKeys=${json.keys.toList()} '
        'clientKeys=${clientMap?.keys.toList()}',
      );
    }

    final assignmentJson = json['assignment'];

    return Job(
      id: json['jobId'] as String? ?? json['id'] as String,
      status: JobStatus.fromString(json['status'] as String),
      categoryId: json['categoryId'] as String? ?? '',
      categoryName: json['categoryName'] as String?,
      description: json['description'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      addressText: json['addressText'] as String?,
      photos: (json['photos'] as List<dynamic>?)?.cast<String>() ?? const [],
      scheduledFor: json['scheduledFor'] as String?,
      clientName: resolvedClientName,
      clientPhone: resolvedClientPhone,
      clientPhotoUrl: resolvedClientPhotoUrl,
      agreedPricePesewas: json['agreedPricePesewas'] as int?,
      shareToken: json['shareToken'] as String?,
      artisansNotified: json['artisansNotified'] as int?,
      createdAt: json['createdAt'] as String?,
      expiresAt: (json['expiresAt'] ??
          json['requestExpiresAt'] ??
          json['expires_at']) as String?,
      assignedArtisanId:
          (json['assignedArtisanId'] ?? json['artisanId']) as String?,
      assignedByAdmin: json['assignedByAdmin'] as String?,
      assignedAt: json['assignedAt'] as String?,
      assignment: assignmentJson is Map<String, dynamic>
          ? JobAssignment.fromJson(assignmentJson)
          : null,
      // Backend may serialise either camelCase (startedAt) or snake_case
      // (started_at) depending on the endpoint — accept both so the
      // mobile keeps working as the API converges.
      startedAt: (json['startedAt'] ?? json['started_at']) as String?,
      completedAt: (json['completedAt'] ?? json['completed_at']) as String?,
      clientPaymentAcknowledgedAt:
          json['clientPaymentAcknowledgedAt'] as String?,
      clientPaymentMethod: json['clientPaymentMethod'] as String?,
    );
  }

  final String id;
  final JobStatus status;
  final String categoryId;
  final String? categoryName;
  final String description;
  final double latitude;
  final double longitude;
  final String? addressText;
  final List<String> photos;
  final String? scheduledFor;
  final String? clientName;
  final String? clientPhone;
  final String? clientPhotoUrl;
  final int? agreedPricePesewas;
  final String? shareToken;
  final int? artisansNotified;
  final String? createdAt;

  /// Absolute backend deadline for the current invitation/bid window.
  /// Request surfaces use this instead of starting a fresh client timer.
  final String? expiresAt;

  /// The artisan this job is assigned to (after client pick OR admin assign).
  final String? assignedArtisanId;

  /// Populated when the job was assigned via admin after zero bids —
  /// the admin user's id. Null for jobs that followed the normal bid flow.
  final String? assignedByAdmin;

  /// When the admin / client assigned the artisan.
  final String? assignedAt;

  /// Server-authored directed-assignment state. Null for normal marketplace
  /// jobs and for responses produced by backend versions before this envelope.
  final JobAssignment? assignment;

  /// ISO timestamp set by the backend when the artisan flips the job to
  /// `in_progress`. Used by the active-job screens (provider + client) to
  /// drive a live elapsed-time ticker. Null until the job has actually
  /// started — both apps should treat null as "no timer yet."
  final String? startedAt;

  /// ISO timestamp set by the backend when the artisan flips the job to
  /// `artisan_marked_complete`. Together with [startedAt] this gives the
  /// final on-the-job duration shown on the completion summary. Null
  /// until the work is finished.
  final String? completedAt;

  /// Parsed [startedAt] in local time, or null if it isn't set / can't be
  /// parsed. Convenience for the UI elapsed-time widget so callers don't
  /// have to defend against a malformed timestamp.
  DateTime? get startedAtDateTime =>
      startedAt == null ? null : DateTime.tryParse(startedAt!)?.toLocal();

  /// Parsed [completedAt] in local time, or null if it isn't set / can't
  /// be parsed.
  DateTime? get completedAtDateTime =>
      completedAt == null ? null : DateTime.tryParse(completedAt!)?.toLocal();

  /// ISO timestamp set by the backend when the client opens the payment
  /// screen and picks a method (any method — cash, momo, card). Null until
  /// the client has acknowledged. Used by the artisan UI to gate the
  /// "Yes, I received payment" button: tapping before this is set returns
  /// 409 CLIENT_PAYMENT_NOT_ACKNOWLEDGED from `artisan-confirm-cash`.
  final String? clientPaymentAcknowledgedAt;

  /// What the client selected on the payment screen — `'cash'`, `'momo'`,
  /// or `'card'`. Null until the client has acknowledged. Lets the artisan
  /// UI tell "client picked Cash, please confirm receipt" apart from
  /// "client picked MoMo, wait for the webhook".
  final String? clientPaymentMethod;

  /// Convenience: has the client confirmed they're paying with cash?
  /// Used to enable the artisan's "Yes, I received payment" CTA.
  bool get isClientCashAcknowledged =>
      clientPaymentAcknowledgedAt != null && clientPaymentMethod == 'cash';

  /// Whether this job reached the admin-assignment fallback path.
  bool get isAdminAssigned =>
      assignment != null ||
      assignedByAdmin != null ||
      status == JobStatus.adminAssigned;

  bool get isOpen => status == JobStatus.open;
  bool get isActive => status.isActive;
  bool get isScheduled => scheduledFor != null;

  Job copyWith({
    String? id,
    JobStatus? status,
    String? categoryId,
    String? categoryName,
    String? description,
    double? latitude,
    double? longitude,
    String? addressText,
    List<String>? photos,
    String? scheduledFor,
    String? clientName,
    String? clientPhone,
    String? clientPhotoUrl,
    int? agreedPricePesewas,
    String? shareToken,
    int? artisansNotified,
    String? createdAt,
    String? expiresAt,
    String? assignedArtisanId,
    String? assignedByAdmin,
    String? assignedAt,
    JobAssignment? assignment,
    String? startedAt,
    String? completedAt,
    String? clientPaymentAcknowledgedAt,
    String? clientPaymentMethod,
  }) {
    return Job(
      id: id ?? this.id,
      status: status ?? this.status,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      addressText: addressText ?? this.addressText,
      photos: photos ?? this.photos,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      clientName: clientName ?? this.clientName,
      clientPhone: clientPhone ?? this.clientPhone,
      clientPhotoUrl: clientPhotoUrl ?? this.clientPhotoUrl,
      agreedPricePesewas: agreedPricePesewas ?? this.agreedPricePesewas,
      shareToken: shareToken ?? this.shareToken,
      artisansNotified: artisansNotified ?? this.artisansNotified,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      assignedArtisanId: assignedArtisanId ?? this.assignedArtisanId,
      assignedByAdmin: assignedByAdmin ?? this.assignedByAdmin,
      assignedAt: assignedAt ?? this.assignedAt,
      assignment: assignment ?? this.assignment,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      clientPaymentAcknowledgedAt:
          clientPaymentAcknowledgedAt ?? this.clientPaymentAcknowledgedAt,
      clientPaymentMethod: clientPaymentMethod ?? this.clientPaymentMethod,
    );
  }
}

/// Job status flow matching the backend enum.
enum JobStatus {
  /// Bid window expired with zero bids — the job is queued for admin
  /// to manually assign an artisan. Not biddable from the mobile app.
  pendingAdmin,

  /// Admin has assigned an artisan. That artisan must now submit a price
  /// to continue the flow. Biddable only for the assigned artisan.
  adminAssigned,

  open,
  queued,
  confirmed,
  artisanEnRoute,
  arrived,
  inProgress,
  artisanMarkedComplete,

  /// Client has kicked off the escrow charge but Paystack hasn't settled it
  /// yet (or the charge is mid-retry). Job sits here until `charge.success`
  /// flips it to [completed], or `charge.failed` reverts it to
  /// [artisanMarkedComplete] so the client can retry.
  pendingPayment,

  completed,
  cancelled;

  /// Parse a snake_case string from the backend.
  static JobStatus fromString(String value) {
    switch (value) {
      case 'pending_admin':
      case 'admin_review':
        return JobStatus.pendingAdmin;
      case 'admin_assigned':
      case 'awaiting_artisan_quote':
        return JobStatus.adminAssigned;
      case 'open':
        return JobStatus.open;
      case 'queued':
        return JobStatus.queued;
      case 'confirmed':
        return JobStatus.confirmed;
      case 'artisan_en_route':
        return JobStatus.artisanEnRoute;
      case 'arrived':
        return JobStatus.arrived;
      case 'in_progress':
        return JobStatus.inProgress;
      case 'artisan_marked_complete':
        return JobStatus.artisanMarkedComplete;
      case 'pending_payment':
        return JobStatus.pendingPayment;
      case 'completed':
        return JobStatus.completed;
      case 'cancelled':
        return JobStatus.cancelled;
      default:
        return JobStatus.open;
    }
  }

  /// Convert to the snake_case string the backend expects.
  String toJson() {
    switch (this) {
      case JobStatus.pendingAdmin:
        return 'pending_admin';
      case JobStatus.adminAssigned:
        return 'admin_assigned';
      case JobStatus.artisanEnRoute:
        return 'artisan_en_route';
      case JobStatus.inProgress:
        return 'in_progress';
      case JobStatus.artisanMarkedComplete:
        return 'artisan_marked_complete';
      case JobStatus.pendingPayment:
        return 'pending_payment';
      default:
        return name;
    }
  }

  bool get isActive =>
      this == confirmed ||
      this == artisanEnRoute ||
      this == arrived ||
      this == inProgress;
}
