import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Backend app-to-app call session.
///
/// The actual audio/WebRTC layer is negotiated over the `/calls` socket
/// namespace. This REST service owns the durable call-session lifecycle:
/// start, join/refresh, accept, decline, and end.
class AppCallSession {
  const AppCallSession({
    required this.callId,
    required this.bookingType,
    required this.bookingId,
    required this.roomName,
    required this.status,
    required this.callerId,
    required this.callerRole,
    required this.callerName,
    required this.calleeId,
    required this.calleeRole,
    required this.calleeName,
    required this.createdAt,
    required this.expiresAt,
    required this.rtcProvider,
    this.endedAt,
    this.rtcToken,
  });

  factory AppCallSession.fromJson(Map<String, dynamic> json) {
    return AppCallSession(
      callId: (json['callId'] ?? json['id']) as String? ?? '',
      bookingType: json['bookingType'] as String? ?? '',
      bookingId: json['bookingId'] as String? ?? '',
      roomName: json['roomName'] as String? ?? '',
      status: json['status'] as String? ?? '',
      callerId: json['callerId'] as String? ?? '',
      callerRole: json['callerRole'] as String? ?? '',
      callerName: json['callerName'] as String?,
      calleeId: json['calleeId'] as String? ?? '',
      calleeRole: json['calleeRole'] as String? ?? '',
      calleeName: json['calleeName'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
      expiresAt: json['expiresAt'] as String? ?? '',
      endedAt: json['endedAt'] as String?,
      rtcProvider: json['rtcProvider'] as String? ?? '',
      rtcToken: json['rtcToken'] is Map
          ? Map<String, dynamic>.from(json['rtcToken'] as Map)
          : null,
    );
  }

  final String callId;
  final String bookingType;
  final String bookingId;
  final String roomName;
  final String status;
  final String callerId;
  final String callerRole;
  final String? callerName;
  final String calleeId;
  final String calleeRole;
  final String? calleeName;
  final String createdAt;
  final String expiresAt;
  final String? endedAt;
  final String rtcProvider;
  final Map<String, dynamic>? rtcToken;

  List<Map<String, dynamic>> get iceServers {
    final rawServers = rtcToken?['iceServers'];
    if (rawServers is! List) return const [];
    final result = <Map<String, dynamic>>[];
    for (final raw in rawServers) {
      if (raw is! Map) continue;
      final server = Map<String, dynamic>.from(raw);
      final urls = server['urls'];
      final validUrls = (urls is String && urls.isNotEmpty) ||
          (urls is List &&
              urls.isNotEmpty &&
              urls.every((url) => url is String && url.isNotEmpty));
      if (!validUrls) continue;
      result.add({
        'urls': urls,
        if (server['username'] is String) 'username': server['username'],
        if (server['credential'] is String) 'credential': server['credential'],
      });
    }
    return result;
  }

  bool get isRinging => status == 'ringing';
  bool get isAccepted => status == 'accepted';
  bool get isTerminal =>
      status == 'declined' || status == 'ended' || status == 'expired';
}

class AppCallService {
  AppCallService(this._dio);
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

  /// POST /calls — Create an in-app voice call session for an active booking.
  Future<AppCallSession> startCall({
    required String bookingType,
    required String bookingId,
  }) async {
    try {
      final response = await _dio.post(
        '/calls',
        data: {
          'bookingType': bookingType,
          'bookingId': bookingId,
        },
      );
      return AppCallSession.fromJson(_unwrap(response) as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /calls/:id/join — Join or refresh an app-call session.
  Future<AppCallSession> joinCall(String callId) =>
      _postCallAction(callId, 'join');

  /// POST /calls/:id/accept — Mark an incoming call accepted.
  Future<AppCallSession> acceptCall(String callId) =>
      _postCallAction(callId, 'accept');

  /// POST /calls/:id/decline — Decline an incoming call.
  Future<AppCallSession> declineCall(String callId) =>
      _postCallAction(callId, 'decline');

  /// POST /calls/:id/end — End an accepted/ringing call.
  Future<AppCallSession> endCall(String callId) =>
      _postCallAction(callId, 'end');

  Future<AppCallSession> _postCallAction(String callId, String action) async {
    try {
      final response = await _dio.post('/calls/$callId/$action');
      return AppCallSession.fromJson(_unwrap(response) as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
