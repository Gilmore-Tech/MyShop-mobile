import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/device_id.dart';

typedef SystemTelemetryPackageInfoLoader = Future<PackageInfo> Function();
typedef SystemTelemetryDelayResolver = Duration Function(int retryAttempt);
typedef SystemTelemetryDeliveryAuthority = Future<bool> Function();

final RegExp _systemTelemetrySafeName = RegExp(r'^[a-zA-Z0-9_./:-]{1,100}$');
final RegExp _systemTelemetryUuidSegment = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _systemTelemetryLongHexSegment = RegExp(
  r'^[0-9a-f]{24,}$',
  caseSensitive: false,
);
final RegExp _systemTelemetryLongNumericSegment = RegExp(r'^\d{8,}$');

String formatSystemTelemetryAppVersion(
  String version,
  String buildNumber, {
  String sourceCommit = const String.fromEnvironment('MYSHOP_SOURCE_COMMIT'),
}) {
  final normalisedCommit = sourceCommit.trim().toLowerCase();
  final suffix = RegExp(r'^[0-9a-f]{40}$').hasMatch(normalisedCommit)
      ? '@${normalisedCommit.substring(0, 12)}'
      : '';
  return '$version+$buildNumber$suffix';
}

/// Returns a bounded route name with query/fragment data removed and common
/// concrete identifiers replaced. Routers should still pass `fullPath` route
/// templates; this is a final privacy boundary for accidental raw paths.
String normaliseSystemTelemetryScreenRoute(String route) {
  var path = route.trim();
  final suffixStart = path.indexOf(RegExp(r'[?#]'));
  if (suffixStart >= 0) path = path.substring(0, suffixStart);
  final segments = path.split('/').map((segment) {
    if (_systemTelemetryUuidSegment.hasMatch(segment) ||
        _systemTelemetryLongHexSegment.hasMatch(segment) ||
        _systemTelemetryLongNumericSegment.hasMatch(segment)) {
      return ':id';
    }
    return segment;
  });
  return _normaliseSystemTelemetryName(segments.join('/'));
}

String _normaliseSystemTelemetryName(String value) {
  final trimmed = value.trim();
  if (_systemTelemetrySafeName.hasMatch(trimmed)) return trimmed;
  final safe = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_./:-]+'), '_');
  return safe.isEmpty
      ? 'unknown'
      : safe.substring(0, safe.length > 100 ? 100 : safe.length);
}

/// Privacy-minimal, best-effort mobile telemetry. Only named screens, app
/// lifecycle states, and explicitly named meaningful actions belong here. Raw
/// taps, scrolling, typed text, chat content, coordinates and credentials are
/// prohibited.
///
/// Delivery is at-least-once rather than exactly-once: confirmed batches are
/// removed, but a transport loss after server acceptance can produce a
/// duplicate event row. Telemetry must never be used as a financial ledger.
class SystemTelemetryService {
  SystemTelemetryService({
    required Dio dio,
    required DeviceIdProvider deviceIdProvider,
    required String app,
    SystemTelemetryPackageInfoLoader? packageInfoLoader,
    SystemTelemetryDelayResolver? delayResolver,
    SystemTelemetryDeliveryAuthority? deliveryAuthority,
  })  : _dio = dio,
        _deviceIdProvider = deviceIdProvider,
        _app = app,
        _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
        _delayResolver = delayResolver ?? _defaultSystemTelemetryDelay,
        _deliveryAuthority = deliveryAuthority;

  static const Set<String> _allowedOutcomes = {
    'success',
    'failure',
    'cancelled',
  };
  static final RegExp _safeCorrelationId = RegExp(r'^[a-zA-Z0-9_-]{1,100}$');
  static final RegExp _sensitiveKey = RegExp(
    r'password|otp|token|secret|phone|message|chat|latitude|longitude|location|account|card|license',
    caseSensitive: false,
  );

  final Dio _dio;
  final DeviceIdProvider _deviceIdProvider;
  final String _app;
  final SystemTelemetryPackageInfoLoader _packageInfoLoader;
  final SystemTelemetryDelayResolver _delayResolver;
  final SystemTelemetryDeliveryAuthority? _deliveryAuthority;
  final List<Map<String, Object?>> _queue = [];
  bool _flushing = false;
  bool _disposed = false;
  bool _authorityCheckInFlight = false;
  int _retryAttempt = 0;
  Timer? _flushTimer;
  String? _lastScreen;
  DateTime? _lastScreenAt;
  Future<PackageInfo>? _packageInfo;

  void trackScreen(String route) {
    final safe = normaliseSystemTelemetryScreenRoute(route);
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
      _normaliseSystemTelemetryName(action),
      outcome: _allowedOutcomes.contains(outcome) ? outcome : 'failure',
      correlationId: _normaliseCorrelationId(correlationId),
      metadata: metadata,
    );
  }

  Future<void> flush() async {
    if (_disposed || _flushing || _queue.isEmpty) return;
    if (!await _canDeliver()) {
      // The endpoint is role-authenticated. Preserve pre-login lifecycle
      // events in memory, but do not create a timer/request that can only
      // receive 401. A later authenticated event will schedule delivery.
      _flushTimer?.cancel();
      _flushTimer = null;
      return;
    }
    // Authority resolution is asynchronous. Re-check mutable state so two
    // concurrent callers cannot both start a batch after awaiting it.
    if (_disposed || _flushing || _queue.isEmpty) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushing = true;
    final count = _queue.length > 50 ? 50 : _queue.length;
    final batch = List<Map<String, Object?>>.from(_queue.take(count));
    var transientFailure = false;
    try {
      final package = await (_packageInfo ??= _packageInfoLoader());
      final deviceId = await _deviceIdProvider.ensureDeviceId();
      final response = await _dio.post<Map<String, dynamic>>(
        '/system-audit/mobile/events',
        data: {
          'app': _app,
          'appVersion': formatSystemTelemetryAppVersion(
            package.version,
            package.buildNumber,
          ),
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
      final accepted = _acceptedTelemetryCount(response.data);
      if (accepted != count) {
        // The ingestion endpoint deliberately returns 200/accepted:0 when its
        // non-blocking telemetry write fails. A transport success therefore
        // is not delivery authority. Retain and retry the complete batch
        // unless the server confirms every event.
        throw StateError(
          'Telemetry batch was not fully accepted by the server.',
        );
      }
      _queue.removeRange(0, count);
      _retryAttempt = 0;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // Permanent client/auth failures cannot become safely attributable
      // later and must not leave a poison event blocking the bounded queue.
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429 &&
          _queue.length >= count) {
        _queue.removeRange(0, count);
        _retryAttempt = 0;
      } else {
        transientFailure = true;
      }
    } catch (_) {
      // Operational telemetry is explicitly non-blocking.
      transientFailure = true;
    } finally {
      if (_queue.length > 500) _queue.removeRange(0, _queue.length - 500);
      _flushing = false;
      if (!_disposed && _queue.isNotEmpty) {
        if (transientFailure) {
          _retryAttempt = min(_retryAttempt + 1, 5);
          _scheduleFlush(_delayResolver(_retryAttempt));
        } else {
          // Drain a queue larger than one request batch without waiting for
          // another user action or lifecycle transition.
          _scheduleFlush(Duration.zero);
        }
      }
    }
  }

  int? _acceptedTelemetryCount(Map<String, dynamic>? response) {
    if (response == null) return null;
    // The API's canonical response is `{success: true, data: {accepted}}`.
    // Keep the historical top-level field as a temporary fallback while old
    // backend/mobile releases age out, but never let it override canonical
    // data when both are present.
    final data = response['data'];
    if (data is Map && data.containsKey('accepted')) {
      return _wholeAcceptedCount(data['accepted']);
    }
    return _wholeAcceptedCount(response['accepted']);
  }

  int? _wholeAcceptedCount(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is num &&
        value.isFinite &&
        value >= 0 &&
        value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
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
      if (!_systemTelemetrySafeName.hasMatch(entry.key) ||
          _sensitiveKey.hasMatch(entry.key)) {
        continue;
      }
      final value = entry.value;
      // Free-form strings can contain typed content or personal data. Named
      // action metadata is deliberately limited to primitive measurements and
      // booleans; the action name carries the categorical meaning.
      if (value is num || value is bool || value == null) {
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
    if (_queue.length >= 25) {
      _flushTimer?.cancel();
      _flushTimer = null;
      unawaited(flush());
    } else {
      // A low-activity session must not keep fewer than 25 events in memory
      // indefinitely. This is one delayed flush, not a permanent poller.
      _scheduleFlush(_delayResolver(0));
    }
  }

  String? _normaliseCorrelationId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || !_safeCorrelationId.hasMatch(trimmed)) return null;
    return trimmed;
  }

  void _scheduleFlush(Duration delay) {
    if (_disposed || _queue.isEmpty || (_flushTimer?.isActive ?? false)) return;
    if (_deliveryAuthority != null) {
      if (_authorityCheckInFlight) return;
      _authorityCheckInFlight = true;
      unawaited(_scheduleFlushWhenAuthorised(delay));
      return;
    }
    _startFlushTimer(delay);
  }

  Future<void> _scheduleFlushWhenAuthorised(Duration delay) async {
    final authorised = await _canDeliver();
    _authorityCheckInFlight = false;
    if (!authorised ||
        _disposed ||
        _queue.isEmpty ||
        (_flushTimer?.isActive ?? false)) {
      return;
    }
    _startFlushTimer(delay);
  }

  Future<bool> _canDeliver() async {
    final authority = _deliveryAuthority;
    if (authority == null) return true;
    try {
      return await authority();
    } catch (_) {
      // Secure-storage availability must never affect the user flow.
      return false;
    }
  }

  void _startFlushTimer(Duration delay) {
    _flushTimer = Timer(delay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }
}

Duration _defaultSystemTelemetryDelay(int retryAttempt) {
  final base = switch (retryAttempt) {
    0 => const Duration(seconds: 10),
    1 => const Duration(seconds: 5),
    2 => const Duration(seconds: 15),
    3 => const Duration(seconds: 30),
    4 => const Duration(minutes: 1),
    _ => const Duration(minutes: 2),
  };
  final jitter = Random().nextInt((base.inMilliseconds ~/ 2) + 1);
  return base + Duration(milliseconds: jitter);
}
