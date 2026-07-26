import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IosAlwaysAuthorizationRequestResult {
  granted,
  notGranted,
  unsupported,
  failed,
}

enum IosLocationAuthorizationStatus {
  notDetermined,
  restricted,
  denied,
  whileInUse,
  always,
  unsupported,
  unavailable,
}

/// Owns the provider app's explicit, staged iOS location authorization flow.
///
/// Core Location requires When In Use authorization before the separate Always
/// request. Reading the exact native state also preserves the distinction
/// between notDetermined and restricted, which geolocator_apple intentionally
/// maps to the same Dart enum value.
///
/// This bridge never grants permission itself: iOS owns the decision and may
/// keep the app at When In Use. Callers must re-read the authoritative
/// geolocator permission after this future completes and offer Settings when
/// Always was not granted.
class IosAlwaysLocationPermissionBridge {
  IosAlwaysLocationPermissionBridge({
    MethodChannel? channel,
    bool Function()? isIos,
  })  : _channel = channel ?? _defaultChannel,
        _isIos = isIos ?? _platformIsIos;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.gilmoretech.myshopprovider/location_authorization',
  );

  static bool _platformIsIos() => Platform.isIOS;

  final MethodChannel _channel;
  final bool Function() _isIos;

  Future<IosLocationAuthorizationStatus> getAuthorizationStatus() {
    return _invokeStatus('getAuthorizationStatus');
  }

  Future<IosLocationAuthorizationStatus> requestWhenInUseAuthorization() {
    return _invokeStatus('requestWhenInUseAuthorization');
  }

  Future<IosAlwaysAuthorizationRequestResult>
      requestAlwaysAuthorization() async {
    if (!_isIos()) {
      return IosAlwaysAuthorizationRequestResult.unsupported;
    }

    final status = await _invokeStatus('requestAlwaysAuthorization');
    switch (status) {
      case IosLocationAuthorizationStatus.always:
        return IosAlwaysAuthorizationRequestResult.granted;
      case IosLocationAuthorizationStatus.unsupported:
        return IosAlwaysAuthorizationRequestResult.unsupported;
      case IosLocationAuthorizationStatus.unavailable:
        return IosAlwaysAuthorizationRequestResult.failed;
      case IosLocationAuthorizationStatus.notDetermined:
      case IosLocationAuthorizationStatus.restricted:
      case IosLocationAuthorizationStatus.denied:
      case IosLocationAuthorizationStatus.whileInUse:
        return IosAlwaysAuthorizationRequestResult.notGranted;
    }
  }

  Future<IosLocationAuthorizationStatus> _invokeStatus(String method) async {
    if (!_isIos()) return IosLocationAuthorizationStatus.unsupported;

    try {
      final status = await _channel
          .invokeMethod<String>(method)
          // Native permission requests are bounded to 30 seconds. Keep a
          // second guard so a broken channel cannot leave Go Online spinning.
          .timeout(const Duration(seconds: 35));
      return _parseStatus(status);
    } on TimeoutException catch (error) {
      debugPrint('[LocationAuthorization] $method timed out: $error');
      return IosLocationAuthorizationStatus.unavailable;
    } on PlatformException catch (error) {
      debugPrint(
        '[LocationAuthorization] $method failed: ${error.code}',
      );
      return IosLocationAuthorizationStatus.unavailable;
    } on MissingPluginException catch (error) {
      debugPrint('[LocationAuthorization] iOS bridge unavailable: $error');
      return IosLocationAuthorizationStatus.unavailable;
    }
  }

  IosLocationAuthorizationStatus _parseStatus(String? status) {
    switch (status) {
      case 'notDetermined':
        return IosLocationAuthorizationStatus.notDetermined;
      case 'restricted':
        return IosLocationAuthorizationStatus.restricted;
      case 'denied':
        return IosLocationAuthorizationStatus.denied;
      case 'whileInUse':
        return IosLocationAuthorizationStatus.whileInUse;
      case 'always':
        return IosLocationAuthorizationStatus.always;
      default:
        return IosLocationAuthorizationStatus.unavailable;
    }
  }
}

final iosAlwaysLocationPermissionBridgeProvider =
    Provider<IosAlwaysLocationPermissionBridge>((_) {
  return IosAlwaysLocationPermissionBridge();
});
