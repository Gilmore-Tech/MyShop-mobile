import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for notification API endpoints.
/// EDD �� 5.2 — Other REST Endpoints
class NotificationService {
  NotificationService(this._dio);
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

  /// GET /notifications — Notification history.
  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get('/notifications', queryParameters: {
        'page': page,
        'limit': limit,
      },);
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /notifications/:id/read — Mark notification as read.
  Future<void> markAsRead(String notificationId) async {
    try {
      await _dio.patch('/notifications/$notificationId/read');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /notifications/register-device — Store the FCM token for the
  /// authenticated user so the backend can send push notifications for
  /// incoming jobs/rides when the app is backgrounded or terminated.
  ///
  /// Call on login and whenever the FCM token refreshes.
  Future<void> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    try {
      await _dio.post(
        '/notifications/register-device',
        data: {
          'fcmToken': fcmToken,
          'platform': platform,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
