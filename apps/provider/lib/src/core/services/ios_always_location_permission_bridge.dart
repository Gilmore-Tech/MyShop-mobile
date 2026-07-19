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

/// Invokes the iOS-only second-stage location prompt.
///
/// The geolocator iOS implementation requests When In Use authorization for
/// an undetermined permission, but it does not upgrade an existing When In Use
/// grant to Always. Core Location requires a separate
/// `CLLocationManager.requestAlwaysAuthorization()` call for that transition.
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

  Future<IosAlwaysAuthorizationRequestResult>
      requestAlwaysAuthorization() async {
    if (!_isIos()) {
      return IosAlwaysAuthorizationRequestResult.unsupported;
    }

    try {
      final status = await _channel
          .invokeMethod<String>('requestAlwaysAuthorization')
          // The native side bounds the system decision window. Keep a second
          // guard here so a broken channel can never leave Go Online spinning.
          .timeout(const Duration(seconds: 35));
      if (status == 'always') {
        return IosAlwaysAuthorizationRequestResult.granted;
      }
      if (status == null || status == 'unavailable') {
        return IosAlwaysAuthorizationRequestResult.failed;
      }
      return IosAlwaysAuthorizationRequestResult.notGranted;
    } on TimeoutException catch (error) {
      debugPrint('[LocationAuthorization] iOS request timed out: $error');
      return IosAlwaysAuthorizationRequestResult.failed;
    } on PlatformException catch (error) {
      debugPrint(
        '[LocationAuthorization] iOS request failed: ${error.code}',
      );
      return IosAlwaysAuthorizationRequestResult.failed;
    } on MissingPluginException catch (error) {
      debugPrint('[LocationAuthorization] iOS bridge unavailable: $error');
      return IosAlwaysAuthorizationRequestResult.failed;
    }
  }
}

final iosAlwaysLocationPermissionBridgeProvider =
    Provider<IosAlwaysLocationPermissionBridge>((_) {
  return IosAlwaysLocationPermissionBridge();
});
