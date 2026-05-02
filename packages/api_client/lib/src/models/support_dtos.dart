import 'package:shared_models/shared_models.dart';

/// Request body for `POST /v1/support/tickets`.
///
/// Backend rules:
///   - `subject` 1–120 chars, `description` 1–4000 chars (server-trimmed).
///   - `attachments` may be empty; each entry must have a `url` already
///     hosted on our storage provider (use [MediaService.uploadSupportAttachment]
///     to obtain).
///   - `priority` is advisory — safety / fraud reports get bumped server-side.
class CreateTicketRequest {
  const CreateTicketRequest({
    required this.category,
    required this.subject,
    required this.description,
    this.priority,
    this.attachments = const [],
    this.referenceType,
    this.referenceId,
  });

  final TicketCategory category;
  final String subject;
  final String description;
  final TicketPriority? priority;
  final List<TicketAttachment> attachments;
  final String? referenceType;
  final String? referenceId;

  Map<String, dynamic> toJson() => {
        'category': category.wire,
        'subject': subject,
        'description': description,
        if (priority != null) 'priority': priority!.wire,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
        if (referenceType != null) 'referenceType': referenceType,
        if (referenceId != null) 'referenceId': referenceId,
      };
}

/// Request body for `POST /v1/support/tickets/:id/messages`.
class PostTicketMessageRequest {
  const PostTicketMessageRequest({
    required this.body,
    this.attachments = const [],
  });

  final String body;
  final List<TicketAttachment> attachments;

  Map<String, dynamic> toJson() => {
        'body': body,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
      };
}

/// Request body for `PATCH /v1/support/tickets/:id/status`.
///
/// Mobile only ever sends `resolved` (user closes their own ticket) or
/// `reopened` (user disagrees with an agent's resolve). Other transitions
/// are agent-controlled.
class UpdateTicketStatusRequest {
  const UpdateTicketStatusRequest({required this.status});

  /// Either `'resolved'` or `'reopened'`.
  final String status;

  Map<String, dynamic> toJson() => {'status': status};
}

/// Backend error codes specific to support endpoints. Matches the
/// `ChatErrorCodes`-style convention from existing services.
class SupportErrorCodes {
  const SupportErrorCodes._();

  static const ticketNotFound = 'TICKET_NOT_FOUND';
  static const ticketClosed = 'TICKET_CLOSED';
  static const notTicketOwner = 'NOT_TICKET_OWNER';
  static const messageEmpty = 'MESSAGE_EMPTY';
  static const messageTooLong = 'MESSAGE_TOO_LONG';
  static const subjectTooLong = 'SUBJECT_TOO_LONG';
  static const descriptionTooLong = 'DESCRIPTION_TOO_LONG';
  static const attachmentTooLarge = 'ATTACHMENT_TOO_LARGE';
  static const tooManyAttachments = 'TOO_MANY_ATTACHMENTS';
  static const rateLimited = 'SUPPORT_RATE_LIMITED';
}
