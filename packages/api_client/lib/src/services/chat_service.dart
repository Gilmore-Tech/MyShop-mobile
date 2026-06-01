import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../models/api_exception.dart';

/// REST client for the chat endpoints.
///
/// All methods throw [ApiException] on failure. Backend error codes
/// surface via [ApiException.errorCode] — callers should switch on
/// [ChatErrorCodes] constants (e.g. [ChatErrorCodes.channelClosed] for
/// the 410, [ChatErrorCodes.notAParticipant] for the 403). For status
/// codes specifically:
///   - 403 → `NOT_A_PARTICIPANT` or `CANNOT_READ_OWN_MESSAGE`
///   - 404 → `BOOKING_NOT_FOUND` or `MESSAGE_NOT_FOUND`
///   - 410 → `CHAT_CHANNEL_CLOSED` (booking completed/cancelled)
///
/// Real-time delivery + typing/read indicators ride on the `/chat`
/// Socket.IO namespace (handled separately) — this REST surface is the
/// history fetch + the send/read fallback when the socket isn't available
/// or the ack times out.
class ChatService {
  ChatService(this._dio);

  final Dio _dio;

  /// `GET /chat/:bookingType/:bookingId/messages` — full history, ascending
  /// by `createdAt`.
  Future<List<ChatMessage>> getMessages(
    ChatBookingType bookingType,
    String bookingId,
  ) async {
    try {
      final response =
          await _dio.get('/chat/${bookingType.wire}/$bookingId/messages');
      final data = _unwrap(response);
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `POST /chat/:bookingType/:bookingId/messages` body `{ message }`.
  ///
  /// Returns the saved message (with backend-assigned `id` and
  /// `createdAt`). Validation: `message` must be 1–2000 UTF-8 chars; the
  /// backend trims and rejects with `MESSAGE_EMPTY` / `MESSAGE_TOO_LONG`
  /// otherwise.
  Future<ChatMessage> sendMessage(
    ChatBookingType bookingType,
    String bookingId, {
    required String message,
  }) async {
    try {
      final response = await _dio.post(
        '/chat/${bookingType.wire}/$bookingId/messages',
        data: {'message': message},
      );
      final data = _unwrap(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Unexpected response from server.',
        );
      }
      return ChatMessage.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `PATCH /chat/messages/:messageId/read` — recipient-only, idempotent.
  ///
  /// Returns the server-assigned `readAt` (UTC). Throws with
  /// [ChatErrorCodes.cannotReadOwnMessage] if the caller authored the
  /// message, or [ChatErrorCodes.messageNotFound] if the id doesn't exist.
  Future<DateTime> markRead(String messageId) async {
    try {
      final response = await _dio.patch('/chat/messages/$messageId/read');
      final data = _unwrap(response);
      if (data is Map<String, dynamic>) {
        final raw = data['readAt'];
        if (raw is String) {
          final parsed = DateTime.tryParse(raw);
          if (parsed != null) return parsed;
        }
      }
      // Endpoint is idempotent — backend may return 200 with no body, in
      // which case we treat the call itself as evidence the read landed
      // and stamp "now" so the UI flips its tick.
      return DateTime.now().toUtc();
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
