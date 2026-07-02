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
  String? _cachedInfo;

  /// Returns the persisted device ID, generating + storing one on first call.
  Future<String> ensureDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    String? stored;
    try {
      stored = await _storage.readDeviceId();
    } catch (_) {
      // Android can restore encrypted preferences without the matching
      // Keystore key after a reinstall. Login must still be able to proceed;
      // SecureTokenStorage will repair its backing store when possible.
      stored = null;
    }
    if (stored != null && stored.isNotEmpty) {
      _cachedId = stored;
      return stored;
    }
    final fresh = _uuid.v4();
    try {
      await _storage.writeDeviceId(fresh);
    } catch (_) {
      // Keep the UUID in memory for this session even if persistence is
      // temporarily unavailable. This avoids failing before the login request.
    }
    _cachedId = fresh;
    return fresh;
  }

  /// Returns the human-readable descriptor expected by the backend auth DTOs.
  /// Returns null if collection fails (callers treat the field as optional).
  Future<String?> readDeviceInfo() async {
    if (_cachedInfo != null) return _cachedInfo;
    try {
      if (Platform.isIOS) {
        final ios = await _deviceInfo.iosInfo;
        _cachedInfo = '${ios.utsname.machine} — iOS ${ios.systemVersion}';
      } else if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        final manufacturer = android.manufacturer.trim();
        final model = android.model.trim();
        final device = manufacturer.isEmpty ||
                model.toLowerCase().startsWith(manufacturer.toLowerCase())
            ? model
            : '$manufacturer $model';
        _cachedInfo = '$device — Android ${android.version.release}';
      } else {
        _cachedInfo = Platform.operatingSystem;
      }
    } catch (_) {
      _cachedInfo = null;
    }
    return _cachedInfo;
  }
}
