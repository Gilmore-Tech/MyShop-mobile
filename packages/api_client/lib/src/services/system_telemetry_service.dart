import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/device_id.dart';

/// Privacy-minimal mobile telemetry. Only named screens, app lifecycle states,
/// and explicitly named meaningful actions belong here. Raw taps, scrolling,
/// typed text, chat content, coordinates and credentials are prohibited.
class SystemTelemetryService {
  SystemTelemetryService({
    required Dio dio,
    required DeviceIdProvider deviceIdProvider,
    required String app,
  })  : _dio = dio,
        _deviceIdProvider = deviceIdProvider,
        _app = app;

  static final RegExp _safeName = RegExp(r'^[a-zA-Z0-9_./:-]{1,100}$');
  static final RegExp _sensitiveKey = RegExp(
    r'password|otp|token|secret|phone|message|chat|latitude|longitude|location|account|card|license',
    caseSensitive: false,
  );

  final Dio _dio;
  final DeviceIdProvider _deviceIdProvider;
  final String _app;
  final List<Map<String, Object?>> _queue = [];
  bool _flushing = false;
  String? _lastScreen;
  DateTime? _lastScreenAt;
  Future<PackageInfo>? _packageInfo;

  void trackScreen(String route) {
    final safe = _normaliseName(route);
    final now = DateTime.now().toUtc();
    if (_lastScreen == safe &&
        _lastScreenAt != null &&
        now.difference(_lastScreenAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastScreen = safe;
    _lastScreenAt = now;
    _enqueue('screen_view', safe, occurredAt: now);
  }

  void trackLifecycle(AppLifecycleState state) {
    _enqueue('app_lifecycle', state.name);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  void trackAction(
    String action, {
    String outcome = 'success',
    String? correlationId,
    Map<String, Object?> metadata = const {},
  }) {
    _enqueue(
      'user_action',
      _normaliseName(action),
      outcome: outcome,
      correlationId: correlationId,
      metadata: metadata,
    );
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    final count = _queue.length > 50 ? 50 : _queue.length;
    final batch = List<Map<String, Object?>>.from(_queue.take(count));
    try {
      final package = await (_packageInfo ??= PackageInfo.fromPlatform());
      final deviceId = await _deviceIdProvider.ensureDeviceId();
      await _dio.post<void>(
        '/system-audit/mobile/events',
        data: {
          'app': _app,
          'appVersion': '${package.version}+${package.buildNumber}',
          'deviceId': deviceId,
          'events': batch,
        },
        options: Options(
          // Telemetry never blocks the UI and should not consume the normal
          // one-minute API timeout while a device is offline.
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      _queue.removeRange(0, count);
    } on DioException catch (error) {
      // 401 means the screen/lifecycle event occurred before or after an
      // authenticated role session. It cannot be safely attributed later.
      if (error.response?.statusCode == 401 && _queue.length >= count) {
        _queue.removeRange(0, count);
      }
    } catch (_) {
      // Operational telemetry is explicitly non-blocking.
    } finally {
      if (_queue.length > 500) _queue.removeRange(0, _queue.length - 500);
      _flushing = false;
    }
  }

  void dispose() {
    unawaited(flush());
  }

  void _enqueue(
    String category,
    String action, {
    String outcome = 'success',
    String? correlationId,
    Map<String, Object?> metadata = const {},
    DateTime? occurredAt,
  }) {
    final safeMetadata = <String, Object?>{};
    for (final entry in metadata.entries.take(20)) {
      if (!_safeName.hasMatch(entry.key) || _sensitiveKey.hasMatch(entry.key))
        continue;
      final value = entry.value;
      if (value is String) {
        safeMetadata[entry.key] =
            value.length > 200 ? value.substring(0, 200) : value;
      } else if (value is num || value is bool || value == null) {
        safeMetadata[entry.key] = value;
      }
    }
    _queue.add({
      'category': category,
      'action': action,
      'outcome': outcome,
      'deviceOccurredAt':
          (occurredAt ?? DateTime.now().toUtc()).toIso8601String(),
      if (correlationId != null) 'correlationId': correlationId,
      if (safeMetadata.isNotEmpty) 'metadata': safeMetadata,
    });
    if (_queue.length >= 25) unawaited(flush());
  }

  String _normaliseName(String value) {
    final trimmed = value.trim();
    if (_safeName.hasMatch(trimmed)) return trimmed;
    final safe = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_./:-]+'), '_');
    return safe.isEmpty
        ? 'unknown'
        : safe.substring(0, safe.length > 100 ? 100 : safe.length);
  }
}
