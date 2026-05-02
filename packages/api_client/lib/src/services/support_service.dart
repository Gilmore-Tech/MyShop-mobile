import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../models/api_exception.dart';
import '../models/support_dtos.dart';

/// REST client for support tickets.
///
/// Backend status codes:
///   - 403 → `NOT_TICKET_OWNER`
///   - 404 → `TICKET_NOT_FOUND`
///   - 410 → `TICKET_CLOSED` (cannot post to a closed ticket)
///   - 413 → `ATTACHMENT_TOO_LARGE` / `TOO_MANY_ATTACHMENTS`
///   - 422 → `MESSAGE_EMPTY` / `MESSAGE_TOO_LONG` /
///           `SUBJECT_TOO_LONG` / `DESCRIPTION_TOO_LONG`
///   - 429 → `SUPPORT_RATE_LIMITED`
class SupportService {
  SupportService(this._dio);

  final Dio _dio;

  /// `POST /v1/support/tickets` — file a new ticket. Returns the persisted
  /// [SupportTicket] (server-assigned id, status defaults to `open`).
  Future<SupportTicket> createTicket(CreateTicketRequest request) async {
    try {
      final response = await _dio.post(
        '/v1/support/tickets',
        data: request.toJson(),
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }
      return SupportTicket.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /v1/support/tickets` — list tickets owned by the caller.
  ///
  /// Forward-only cursor pagination. Pass [cursor] from the previous
  /// page's [TicketPage.nextCursor]; null on the first call.
  Future<TicketPage<SupportTicket>> listTickets({
    String? cursor,
    int limit = 20,
    TicketStatus? statusFilter,
  }) async {
    try {
      final response = await _dio.get(
        '/v1/support/tickets',
        queryParameters: {
          'limit': limit,
          if (cursor != null) 'cursor': cursor,
          if (statusFilter != null) 'status': statusFilter.wire,
        },
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        return const TicketPage(items: []);
      }
      return TicketPage.fromJson(data, SupportTicket.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /v1/support/tickets/:id` — header for the detail screen
  /// (subject, status, last message preview, etc.). Use [getMessages] for
  /// the chat thread.
  Future<SupportTicket> getTicket(String ticketId) async {
    try {
      final response = await _dio.get('/v1/support/tickets/$ticketId');
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }
      return SupportTicket.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `GET /v1/support/tickets/:id/messages` — chat history, ascending by
  /// `createdAt`. Forward-only cursor pagination — older messages page
  /// in as the user scrolls back.
  Future<TicketPage<TicketMessage>> getMessages(
    String ticketId, {
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '/v1/support/tickets/$ticketId/messages',
        queryParameters: {
          'limit': limit,
          if (cursor != null) 'cursor': cursor,
        },
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        return const TicketPage(items: []);
      }
      return TicketPage.fromJson(data, TicketMessage.fromJson);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `POST /v1/support/tickets/:id/messages` — reply on an open ticket.
  ///
  /// Validation: `body` 1–4000 UTF-8 chars; backend trims + rejects with
  /// `MESSAGE_EMPTY` / `MESSAGE_TOO_LONG` otherwise. A successful post
  /// flips ticket status from `waiting_user` → `open` server-side.
  Future<TicketMessage> postMessage(
    String ticketId,
    PostTicketMessageRequest request,
  ) async {
    try {
      final response = await _dio.post(
        '/v1/support/tickets/$ticketId/messages',
        data: request.toJson(),
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }
      return TicketMessage.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `PATCH /v1/support/tickets/:id/status` — user-initiated state change.
  /// Mobile only sends `resolved` (close my ticket) or `reopened`
  /// (re-open a recently resolved ticket within 7 days).
  Future<SupportTicket> updateStatus(
    String ticketId,
    UpdateTicketStatusRequest request,
  ) async {
    try {
      final response = await _dio.patch(
        '/v1/support/tickets/$ticketId/status',
        data: request.toJson(),
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }
      return SupportTicket.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `POST /v1/support/tickets/:id/messages/read` — best-effort, idempotent.
  /// Marks every agent/system message up to and including [upToMessageId]
  /// as read. Used when the user opens / resumes the ticket detail.
  Future<void> markRead(String ticketId, {String? upToMessageId}) async {
    try {
      await _dio.post(
        '/v1/support/tickets/$ticketId/messages/read',
        data: {
          if (upToMessageId != null) 'upToMessageId': upToMessageId,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  dynamic _unwrap(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic> && body['success'] == true) {
      return body['data'];
    }
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }
}
