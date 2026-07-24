import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum LiveActivityBridgeEventType {
  pushToStartToken,
  activityUpdateToken,
  activityEnded,
  activitiesEnabled,
  unknown,
}

@immutable
class LiveActivityRegistration {
  const LiveActivityRegistration({
    required this.activityId,
    required this.requestId,
    required this.offerId,
    required this.requestType,
    required this.expiresAt,
    this.updateToken,
  });

  final String activityId;
  final String requestId;
  final String offerId;
  final String requestType;
  final DateTime expiresAt;
  final String? updateToken;

  static LiveActivityRegistration? fromMap(Map<String, dynamic> map) {
    final activityId = _string(map['activityId']);
    final requestId = _string(map['requestId']);
    final offerId = _string(map['offerId']);
    final requestType = normaliseLiveActivityRequestType(map['requestType']);
    final expiresAt = _dateTime(map['expiresAt']);
    if (activityId == null ||
        requestId == null ||
        offerId == null ||
        requestType == null ||
        expiresAt == null) {
      return null;
    }
    return LiveActivityRegistration(
      activityId: activityId,
      requestId: requestId,
      offerId: offerId,
      requestType: requestType,
      expiresAt: expiresAt,
      updateToken: _string(map['updateToken'] ?? map['token']),
    );
  }
}

@immutable
class LiveActivityBridgeEvent {
  const LiveActivityBridgeEvent({
    required this.type,
    this.token,
    this.activity,
    this.activitiesEnabled,
  });

  final LiveActivityBridgeEventType type;
  final String? token;
  final LiveActivityRegistration? activity;
  final bool? activitiesEnabled;
}

@immutable
class LiveActivityBridgeState {
  const LiveActivityBridgeState({
    this.pushToStartToken,
    this.activities = const <LiveActivityRegistration>[],
    this.activitiesEnabled,
  });

  final String? pushToStartToken;
  final List<LiveActivityRegistration> activities;
  final bool? activitiesEnabled;
}

@visibleForTesting
String? normaliseLiveActivityRequestType(Object? value) {
  final raw = _string(value)?.toLowerCase().replaceAll('.', '_');
  return switch (raw) {
    'ride' || 'ride_request' => 'ride',
    'job' || 'job_request' || 'artisan_job' => 'job',
    _ => null,
  };
}

@visibleForTesting
LiveActivityBridgeEvent? liveActivityBridgeEventFromMap(
  Map<String, dynamic> map,
) {
  final rawType = _string(map['type']);
  final type = switch (rawType) {
    'pushToStartToken' => LiveActivityBridgeEventType.pushToStartToken,
    'activityUpdateToken' => LiveActivityBridgeEventType.activityUpdateToken,
    'activityEnded' => LiveActivityBridgeEventType.activityEnded,
    'activitiesEnabled' => LiveActivityBridgeEventType.activitiesEnabled,
    _ => LiveActivityBridgeEventType.unknown,
  };
  final activity = LiveActivityRegistration.fromMap(map);
  final token = _string(map['token'] ?? map['pushToStartToken']);
  if (type == LiveActivityBridgeEventType.pushToStartToken && token == null) {
    return null;
  }
  if ((type == LiveActivityBridgeEventType.activityUpdateToken ||
          type == LiveActivityBridgeEventType.activityEnded) &&
      activity == null) {
    return null;
  }
  final activitiesEnabled = map['enabled'] is bool
      ? map['enabled'] as bool
      : map['activitiesEnabled'] is bool
          ? map['activitiesEnabled'] as bool
          : null;
  if (type == LiveActivityBridgeEventType.activitiesEnabled &&
      activitiesEnabled == null) {
    return null;
  }
  return LiveActivityBridgeEvent(
    type: type,
    token: token,
    activity: activity,
    activitiesEnabled: activitiesEnabled,
  );
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _dateTime(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    );
  }
  final raw = _string(value);
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

/// Native ActivityKit bridge for the provider app.
///
/// Token delivery uses both a snapshot and an event stream. The snapshot is
/// essential because an ActivityKit push can wake native iOS before Flutter is
/// attached, in which case a stream-only implementation would lose the update
/// token that the backend needs to end the card.
class LiveActivityService {
  LiveActivityService._();

  static final LiveActivityService instance = LiveActivityService._();

  static const MethodChannel _methods = MethodChannel(
    'com.gilmoretech.myshop/live_activity',
  );
  static const EventChannel _events = EventChannel(
    'com.gilmoretech.myshop/live_activity/events',
  );

  Stream<LiveActivityBridgeEvent>? _eventStream;

  Stream<LiveActivityBridgeEvent> get events {
    if (!Platform.isIOS) return const Stream<LiveActivityBridgeEvent>.empty();
    return _eventStream ??= _events
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => liveActivityBridgeEventFromMap(
              Map<String, dynamic>.from(event as Map),
            ))
        .where((event) => event != null)
        .cast<LiveActivityBridgeEvent>()
        .asBroadcastStream();
  }

  Future<LiveActivityBridgeState> getState() async {
    if (!Platform.isIOS) return const LiveActivityBridgeState();
    try {
      final raw = await _methods.invokeMapMethod<Object?, Object?>('getState');
      if (raw == null) return const LiveActivityBridgeState();
      final state = <String, dynamic>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
      final activities = <LiveActivityRegistration>[];
      final rawActivities = state['activities'];
      if (rawActivities is List) {
        for (final rawActivity in rawActivities) {
          if (rawActivity is! Map) continue;
          final parsed = LiveActivityRegistration.fromMap(
            Map<String, dynamic>.from(rawActivity),
          );
          if (parsed != null) activities.add(parsed);
        }
      }
      return LiveActivityBridgeState(
        pushToStartToken: _string(state['pushToStartToken']),
        activities: activities,
        activitiesEnabled: state['activitiesEnabled'] is bool
            ? state['activitiesEnabled'] as bool
            : null,
      );
    } on MissingPluginException {
      return const LiveActivityBridgeState();
    } catch (error) {
      debugLog(() => '[LiveActivity] getState failed: $error');
      return const LiveActivityBridgeState();
    }
  }

  Future<void> endRequest({
    required String requestId,
    String? offerId,
    String? requestType,
    String reason = 'resolved',
  }) async {
    if (!Platform.isIOS || requestId.isEmpty) return;
    final normalisedRequestType = normaliseLiveActivityRequestType(requestType);
    try {
      await _methods.invokeMethod<int>('endRequest', <String, String>{
        'requestId': requestId,
        if (offerId != null && offerId.isNotEmpty) 'offerId': offerId,
        if (normalisedRequestType != null) 'requestType': normalisedRequestType,
        'reason': reason,
      });
    } on MissingPluginException {
      // Expected in tests and builds without the iOS 16.1 extension.
    } catch (error) {
      debugLog(() => '[LiveActivity] endRequest failed: $error');
    }
  }

  Future<void> endAll({String reason = 'signed_out'}) async {
    if (!Platform.isIOS) return;
    try {
      await _methods.invokeMethod<int>(
        'endAll',
        <String, String>{'reason': reason},
      );
    } on MissingPluginException {
      // Expected in tests and builds without the iOS 16.1 extension.
    } catch (error) {
      debugLog(() => '[LiveActivity] endAll failed: $error');
    }
  }
}
