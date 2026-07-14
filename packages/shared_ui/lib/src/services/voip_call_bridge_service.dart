import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

enum VoipCallBridgeEventType {
  tokenUpdated,
  tokenInvalidated,
  incomingCall,
  callAccepted,
  callDeclined,
  callEnded,
  unknown,
}

class VoipCallBridgeEvent {
  const VoipCallBridgeEvent({
    required this.type,
    required this.payload,
  });

  factory VoipCallBridgeEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = switch (map['type'] as String?) {
      'voipToken' => VoipCallBridgeEventType.tokenUpdated,
      'voipTokenInvalidated' => VoipCallBridgeEventType.tokenInvalidated,
      'incomingCall' => VoipCallBridgeEventType.incomingCall,
      'callAccepted' => VoipCallBridgeEventType.callAccepted,
      'callDeclined' => VoipCallBridgeEventType.callDeclined,
      'callEnded' => VoipCallBridgeEventType.callEnded,
      _ => VoipCallBridgeEventType.unknown,
    };

    return VoipCallBridgeEvent(
      type: type,
      payload: Map<String, dynamic>.from(map),
    );
  }

  final VoipCallBridgeEventType type;
  final Map<String, dynamic> payload;

  String? get token => payload['token'] as String?;
  String? get callId => payload['callId'] as String?;
  String? get actionId => payload['actionId'] as String?;
}

class VoipCallBridgeService {
  VoipCallBridgeService._();

  static final VoipCallBridgeService instance = VoipCallBridgeService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'com.gilmoretech.myshop/voip_call',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.gilmoretech.myshop/voip_call/events',
  );

  Stream<VoipCallBridgeEvent>? _events;

  Stream<VoipCallBridgeEvent> get events {
    if (!Platform.isIOS) return const Stream<VoipCallBridgeEvent>.empty();
    return _events ??= _eventChannel.receiveBroadcastStream().where((event) {
      return event is Map;
    }).map((event) {
      return VoipCallBridgeEvent.fromMap(event as Map<dynamic, dynamic>);
    });
  }

  Future<String?> getVoipToken() async {
    if (!Platform.isIOS) return null;
    return _methodChannel.invokeMethod<String>('getVoipToken');
  }

  Future<void> showIncomingCall(Map<String, dynamic> payload) async {
    if (!Platform.isIOS) return;
    await _methodChannel.invokeMethod<void>('showIncomingCall', payload);
  }

  Future<void> endCall(String callId) async {
    if (!Platform.isIOS || callId.isEmpty) return;
    await _methodChannel.invokeMethod<void>('endCall', {'callId': callId});
  }

  /// Requests CallKit's canonical Answer action for an active native call.
  /// Returns false when this call was never reported to CallKit, allowing the
  /// Flutter incoming screen to fall back to the REST accept path.
  Future<bool> answerCall(String callId) async {
    if (!Platform.isIOS || callId.isEmpty) return false;
    return await _methodChannel.invokeMethod<bool>(
          'answerCall',
          {'callId': callId},
        ) ??
        false;
  }

  Future<void> acknowledgeCallAction(String? actionId) async {
    if (!Platform.isIOS || actionId == null || actionId.isEmpty) return;
    await _methodChannel.invokeMethod<void>(
      'acknowledgeCallAction',
      {'actionId': actionId},
    );
  }
}
