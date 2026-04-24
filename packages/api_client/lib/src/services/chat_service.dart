import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for chat API endpoints.
/// EDD § 5.2 — Chat messages for active bookings
class ChatService {
  ChatService(this._dio);
  final Dio _dio;

  dynamic _unwrap(Response response) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) return body['data'];
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }

  /// GET /chat/:type/:id/messages — Get chat messages for a booking.
  /// [type] is "ride" or "job".
  Future<List<dynamic>> getMessages(String type, String bookingId) async {
    try {
      final response = await _dio.get('/chat/$type/$bookingId/messages');
      return _unwrap(response) as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /chat/:type/:id/messages — Send a chat message.
  Future<Map<String, dynamic>> sendMessage(
    String type,
    String bookingId, {
    required String content,
  }) async {
    try {
      final response =
          await _dio.post('/chat/$type/$bookingId/messages', data: {
        'content': content,
      },);
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
