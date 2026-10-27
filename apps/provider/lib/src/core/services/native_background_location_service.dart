import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Starts the OS-owned location worker that survives Flutter isolate
/// suspension when the screen locks. The credential is location-only and is
/// bound server-side to one exact Online epoch.
class NativeBackgroundLocationService {
  NativeBackgroundLocationService._();

  static const MethodChannel _channel = MethodChannel(
    'com.gilmoretech.myshopprovider/background_location',
  );

  static Future<void> start({
    required String baseUrl,
    required String credential,
    required String onlineSessionId,
  }) async {
    if (credential.trim().isEmpty || onlineSessionId.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>('start', <String, Object>{
        'endpoint':
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/location/provider/native',
        'credential': credential,
        'onlineSessionId': onlineSessionId,
      });
    } on MissingPluginException {
      // Unit/widget tests and unsupported desktop targets have no native host.
    } on PlatformException catch (error) {
      debugPrint('[NativeLocation] start failed: ${error.code}');
    } catch (error) {
      // Availability authority must not fail because a platform messenger is
      // unavailable during startup, tests, or an unsupported host lifecycle.
      debugPrint('[NativeLocation] start unavailable: $error');
    }
  }

  static Future<void> stop({String? expectedOnlineSessionId}) async {
    try {
      await _channel.invokeMethod<void>('stop', <String, Object?>{
        'expectedOnlineSessionId': expectedOnlineSessionId,
      });
    } on MissingPluginException {
      // Unit/widget tests and unsupported desktop targets have no native host.
    } on PlatformException catch (error) {
      debugPrint('[NativeLocation] stop failed: ${error.code}');
    } catch (error) {
      // Server-confirmed Offline/logout remains authoritative even when the
      // native host has already gone away. The exact-session server fence also
      // prevents any delayed native upload from reviving this session.
      debugPrint('[NativeLocation] stop unavailable: $error');
    }
  }
}
