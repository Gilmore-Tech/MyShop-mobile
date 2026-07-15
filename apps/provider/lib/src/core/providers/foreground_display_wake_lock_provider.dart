import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lifecycle_provider.dart';
import 'provider_status_provider.dart';

const MethodChannel _displayChannel = MethodChannel(
  'com.gilmoretech.myshopprovider/display',
);

/// Keeps the screen awake while a provider is online/busy and actively using
/// the foreground app.
///
/// This is intentionally separate from background location sync. When the app
/// is paused/hidden, the wakelock is released so the user can lock the screen
/// normally while the background sync provider continues location continuity.
final foregroundDisplayWakeLockProvider = Provider<void>((ref) {
  final isForegrounded = ref.watch(appForegroundedProvider);
  final status = ref.watch(providerStatusProvider);
  final shouldKeepScreenOn =
      isForegrounded && (status.isOnline || status.isBusy);

  unawaited(_setKeepScreenOn(shouldKeepScreenOn));

  ref.onDispose(() {
    unawaited(_setKeepScreenOn(false));
  });
});

Future<void> _setKeepScreenOn(bool enabled) async {
  try {
    await _displayChannel.invokeMethod<void>(
      'setKeepScreenOn',
      <String, Object?>{'enabled': enabled},
    );
    debugPrint('[Display] keepScreenOn=$enabled');
  } on MissingPluginException catch (e) {
    debugPrint('[Display] keepScreenOn unsupported: $e');
  } on PlatformException catch (e) {
    debugPrint('[Display] keepScreenOn failed: ${e.message ?? e.code}');
  } catch (e) {
    debugPrint('[Display] keepScreenOn error: $e');
  }
}

/// Allows only the active Android voice-call surface to appear above the
/// keyguard. Request/detail routes remain behind device authentication.
Future<void> setCallLockScreenAccess(bool enabled) async {
  if (!Platform.isAndroid) return;
  try {
    await _displayChannel.invokeMethod<void>(
      'setCallLockScreenAccess',
      <String, Object?>{'enabled': enabled},
    );
  } on MissingPluginException catch (e) {
    debugPrint('[Display] call lock-screen access unsupported: $e');
  } on PlatformException catch (e) {
    debugPrint(
      '[Display] call lock-screen access failed: ${e.message ?? e.code}',
    );
  } catch (e) {
    debugPrint('[Display] call lock-screen access error: $e');
  }
}
