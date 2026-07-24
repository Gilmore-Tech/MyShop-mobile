import 'dart:async';
import 'dart:developer' as platform_developer;

import 'package:flutter/foundation.dart';

/// Installs the process-wide mobile diagnostic policy for the current isolate.
///
/// Flutter's [debugPrint] still emits in profile and release builds unless the
/// application replaces it. MyShop diagnostics can contain operational values
/// supplied by the API or notification payloads, so non-debug artifacts fail
/// closed and emit none of those strings to the device log.
void installMobileProductionLogPolicy() {
  if (!kDebugMode) {
    debugPrint = _discardDiagnostic;
  }
}

void _discardDiagnostic(String? message, {int? wrapWidth}) {}

/// Lazily evaluates a diagnostic only in a debug artifact.
///
/// The callback is important: interpolated payloads and errors are not even
/// converted to strings in profile/release artifacts. Keeping the remaining
/// signature aligned with `dart:developer.log` makes existing call sites easy
/// to route through this boundary.
void debugLog(
  String Function() message, {
  DateTime? time,
  int? sequenceNumber,
  int level = 0,
  String name = '',
  Zone? zone,
  Object? error,
  StackTrace? stackTrace,
}) {
  if (!kDebugMode) return;
  platform_developer.log(
    message(),
    time: time,
    sequenceNumber: sequenceNumber,
    level: level,
    name: name,
    zone: zone,
    error: error,
    stackTrace: stackTrace,
  );
}
