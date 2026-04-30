import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../http/token_storage.dart';

/// Generates and caches a stable per-install UUID, plus collects optional
/// device descriptors (model, OS version) used for backend session metadata.
///
/// The UUID is persisted via [TokenStorage] and survives logout — it
/// represents the install, not the user. On uninstall + reinstall the user
/// will be issued a new ID, which the backend will see as a new device.
class DeviceIdProvider {
  DeviceIdProvider(this._storage, [DeviceInfoPlugin? deviceInfo])
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  static const _uuid = Uuid();
  final TokenStorage _storage;
  final DeviceInfoPlugin _deviceInfo;

  String? _cachedId;
  Map<String, dynamic>? _cachedInfo;

  /// Returns the persisted device ID, generating + storing one on first call.
  Future<String> ensureDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    final stored = await _storage.readDeviceId();
    if (stored != null && stored.isNotEmpty) {
      _cachedId = stored;
      return stored;
    }
    final fresh = _uuid.v4();
    await _storage.writeDeviceId(fresh);
    _cachedId = fresh;
    return fresh;
  }

  /// Returns a JSON-serialisable descriptor for the device. Safe to send
  /// alongside login/register requests. Returns null if collection fails
  /// (callers should treat the field as optional).
  Future<Map<String, dynamic>?> readDeviceInfo() async {
    if (_cachedInfo != null) return _cachedInfo;
    try {
      if (Platform.isIOS) {
        final ios = await _deviceInfo.iosInfo;
        _cachedInfo = {
          'platform': 'ios',
          'model': ios.utsname.machine,
          'osVersion': ios.systemVersion,
          'name': ios.name,
        };
      } else if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        _cachedInfo = {
          'platform': 'android',
          'model': android.model,
          'manufacturer': android.manufacturer,
          'osVersion': android.version.release,
          'sdkInt': android.version.sdkInt,
        };
      } else {
        _cachedInfo = {'platform': Platform.operatingSystem};
      }
    } catch (_) {
      _cachedInfo = null;
    }
    return _cachedInfo;
  }
}
