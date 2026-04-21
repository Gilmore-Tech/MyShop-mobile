import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Payload keys embedded in local/FCM notifications so the tap handler can
/// route to the right screen.
class NotificationPayload {
  static const keyType = 'type';
  static const keyJobId = 'jobId';
  static const keyRideId = 'rideId';

  static const typeJobRequest = 'job_request';
  static const typeRideRequest = 'ride_request';
}

/// Wraps `flutter_local_notifications` and exposes a single entry point for:
///   - Foreground attention alerts (sound/vibrate when a modal is shown)
///   - Background notifications (displayed when FCM pushes arrive while
///     the app is minimised or terminated)
///
/// The same channel is reused by the FCM background handler so pushes and
/// in-app alerts share the same sound/importance.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Android channel used for all job + ride alerts. HIGH importance so the
  /// OS plays a sound and shows the heads-up banner.
  static const AndroidNotificationChannel _jobAlertsChannel =
      AndroidNotificationChannel(
    'job_alerts',
    'Job & Ride Requests',
    description: 'Incoming job and ride requests that need your attention.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  bool _initialised = false;

  /// Called from the tap handler — consumers (the router) set this once
  /// and the service forwards payloads to it.
  void Function(Map<String, dynamic> payload)? _onTap;

  set onTap(void Function(Map<String, dynamic> payload)? handler) =>
      _onTap = handler;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final decoded = json.decode(raw);
          if (decoded is Map<String, dynamic>) _onTap?.call(decoded);
        } catch (e) {
          debugPrint('[LocalNotificationService] bad payload: $e');
        }
      },
    );

    // Register the Android channel (no-op on iOS).
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_jobAlertsChannel);
    await androidPlugin?.requestNotificationsPermission();
  }

  /// Show a persistent banner for an incoming job. Used by FCM background
  /// handler when the app is minimised — tapping takes the user back into
  /// the full job-request screen via [onTap].
  Future<void> showJobRequest({
    required String jobId,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      _hash(jobId),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _jobAlertsChannel.id,
          _jobAlertsChannel.name,
          channelDescription: _jobAlertsChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: json.encode({
        NotificationPayload.keyType: NotificationPayload.typeJobRequest,
        NotificationPayload.keyJobId: jobId,
      }),
    );
  }

  /// Same as [showJobRequest] but for incoming ride events.
  Future<void> showRideRequest({
    required String rideId,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      _hash(rideId),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _jobAlertsChannel.id,
          _jobAlertsChannel.name,
          channelDescription: _jobAlertsChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: json.encode({
        NotificationPayload.keyType: NotificationPayload.typeRideRequest,
        NotificationPayload.keyRideId: rideId,
      }),
    );
  }

  /// Play the system alert sound and fire heavy haptic — used while the
  /// app is in the foreground and the modal is already visible (no banner
  /// needed since the UI is already grabbing attention).
  ///
  /// Fires the haptic twice and the sound once; effective on iOS + Android
  /// without needing a custom asset.
  Future<void> playForegroundAlert() async {
    await HapticFeedback.heavyImpact();
    await SystemSound.play(SystemSoundType.alert);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await HapticFeedback.heavyImpact();
  }

  /// Stable non-negative notification id from a job/ride id.
  int _hash(String id) => id.hashCode & 0x7fffffff;
}

/// Riverpod provider so consumers can `ref.read(notificationServiceProvider)`.
final notificationServiceProvider = Provider<LocalNotificationService>((_) {
  return LocalNotificationService.instance;
});
