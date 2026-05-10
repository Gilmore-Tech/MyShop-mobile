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
      final response = await _dio.get(
        '/notifications',
        queryParameters: {
          'page': page,
          'limit': limit,
        },
      );
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
  /// authenticated (user, role) identity so the backend can route push
  /// notifications correctly when the app is backgrounded or terminated.
  ///
  /// `role` MUST match the active role from the JWT — passing the wrong
  /// value silently routes another role's pushes to this device. Backend
  /// upserts on the composite key (userId, role, platform), so calling
  /// this on every role login keeps each role's FCM token alive in
  /// parallel on the same handset.
  ///
  /// Call on login and whenever the FCM token refreshes (and after a
  /// role-switch, since role-switch in the Provider app is technically
  /// a fresh login under a different /auth/login/{role} endpoint).
  Future<void> registerDevice({
    required String fcmToken,
    required String platform,
    required String role,
  }) async {
    try {
      await _dio.post(
        '/notifications/register-device',
        data: {
          'fcmToken': fcmToken,
          'platform': platform,
          // role omitted from the body — backend reads it from the
          // bearer JWT (`@CurrentUser('role')`). Including it here would
          // be a noop server-side and risk drift if the JWT and body
          // disagreed. Kept on the method signature so callers must
          // think about which role they're registering.
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
