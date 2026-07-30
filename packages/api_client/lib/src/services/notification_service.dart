import 'package:dio/dio.dart';

import '../http/auth_interceptor.dart';
import '../http/token_storage.dart';
import '../models/api_exception.dart';

/// Service for notification API endpoints.
/// EDD �� 5.2 — Other REST Endpoints
class NotificationService {
  NotificationService(this._dio);
  final Dio _dio;

  Options _ownedSessionOptions(AuthSessionIdentity expectedIdentity) => Options(
        extra: {
          AuthInterceptor.expectedSessionIdentityExtra: expectedIdentity,
        },
      );

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
    required AuthSessionIdentity expectedIdentity,
    // v2 adds native ActivityKit delivery receipts so a Live Activity can be
    // the only visible iOS request surface. Older v1 installs remain on the
    // standard APNs fallback during a staged rollout.
    int? offerReceiptVersion = 2,
  }) async {
    try {
      await _dio.post(
        '/notifications/register-device',
        data: {
          'fcmToken': fcmToken,
          'platform': platform,
          if (offerReceiptVersion != null)
            'offerReceiptVersion': offerReceiptVersion,
          // role omitted from the body — backend reads it from the
          // bearer JWT (`@CurrentUser('role')`). Including it here would
          // be a noop server-side and risk drift if the JWT and body
          // disagreed. Kept on the method signature so callers must
          // think about which role they're registering.
        },
        options: _ownedSessionOptions(expectedIdentity),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /notifications/register-voip-device — Store the iOS APNs PushKit
  /// token for CallKit incoming calls.
  ///
  /// This is intentionally separate from [registerDevice]. FCM/APNs alert
  /// tokens use the normal APNs topic, while PushKit VoIP tokens use the
  /// app's `.voip` topic and are only valid on iOS.
  Future<void> registerVoipDevice({
    required String voipToken,
    required AuthSessionIdentity expectedIdentity,
  }) async {
    try {
      await _dio.post(
        '/notifications/register-voip-device',
        data: {
          'voipToken': voipToken,
          'platform': 'ios',
        },
        options: _ownedSessionOptions(expectedIdentity),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /notifications/register-voip-device — Clear the iOS PushKit token
  /// binding when PushKit invalidates it or the app logs out.
  Future<void> unregisterVoipDevice({
    String? voipToken,
    required AuthSessionIdentity expectedIdentity,
  }) async {
    try {
      await _dio.delete(
        '/notifications/register-voip-device',
        data: {
          'platform': 'ios',
          if (voipToken != null && voipToken.isNotEmpty) 'voipToken': voipToken,
        },
        options: _ownedSessionOptions(expectedIdentity),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /notifications/register-live-activity-device — Bind the iOS
  /// ActivityKit push-to-start token to the authenticated provider's current
  /// FCM device registration.
  ///
  /// ActivityKit rotates this token independently of FCM, so callers should
  /// invoke this on login and whenever the native token update stream emits.
  Future<void> registerLiveActivityDevice({
    required String pushToStartToken,
    required AuthSessionIdentity expectedIdentity,
  }) async {
    try {
      await _dio.post(
        '/notifications/register-live-activity-device',
        data: {
          'platform': 'ios',
          'pushToStartToken': pushToStartToken,
        },
        options: _ownedSessionOptions(expectedIdentity),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /notifications/register-live-activity-device — Remove the current
  /// provider/device push-to-start binding on logout or native invalidation.
  Future<void> unregisterLiveActivityDevice({
    String? pushToStartToken,
    required AuthSessionIdentity expectedIdentity,
  }) async {
    try {
      await _dio.delete(
        '/notifications/register-live-activity-device',
        data: {
          'platform': 'ios',
          if (pushToStartToken != null && pushToStartToken.isNotEmpty)
            'pushToStartToken': pushToStartToken,
        },
        options: _ownedSessionOptions(expectedIdentity),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /notifications/register-live-activity — Register the per-activity
  /// ActivityKit update token that the backend must use to end an offer card.
  /// The push-to-start token cannot update or end an already-started activity.
  Future<void> registerLiveActivity({
    required String activityId,
    required String updateToken,
    required String offerId,
    required String requestType,
    required String requestId,
    required DateTime expiresAt,
    required AuthSessionIdentity expectedIdentity,
  }) async {
    try {
      await _dio.post(
        '/notifications/register-live-activity',
        data: {
          'platform': 'ios',
          'activityId': activityId,
          'updateToken': updateToken,
          'offerId': offerId,
          'requestType': requestType,
          'requestId': requestId,
          'expiresAt': expiresAt.toUtc().toIso8601String(),
        },
        options: _ownedSessionOptions(expectedIdentity),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /notifications/register-live-activity — Remove one stale
  /// per-activity update token after ActivityKit reports that it ended.
  Future<void> unregisterLiveActivity({
    required String activityId,
    String? updateToken,
    required AuthSessionIdentity expectedIdentity,
  }) async {
    try {
      await _dio.delete(
        '/notifications/register-live-activity',
        data: {
          'platform': 'ios',
          'activityId': activityId,
          if (updateToken != null && updateToken.isNotEmpty)
            'updateToken': updateToken,
        },
        options: _ownedSessionOptions(expectedIdentity),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
