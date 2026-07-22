import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/calls/screens/in_app_call_screen.dart';

class _ControlledCallService extends AppCallService {
  _ControlledCallService() : super(Dio());

  final response = Completer<AppCallSession>();
  int joinCalls = 0;

  @override
  Future<AppCallSession> joinCall(String callId) {
    joinCalls += 1;
    return response.future;
  }
}

class _MockCallSocket extends Mock implements AppCallSocketService {}

void main() {
  testWidgets(
      'provider call refresh timer does not overlap a slow initial join',
      (tester) async {
    final service = _ControlledCallService();
    final socket = _MockCallSocket();
    when(() => socket.sessionStream)
        .thenAnswer((_) => const Stream<AppCallSession>.empty());
    when(() => socket.joinCall(any())).thenAnswer((_) async {});
    when(() => socket.leaveCall(any())).thenReturn(null);
    when(socket.disconnect).thenReturn(null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appCallServiceProvider.overrideWithValue(service),
          appCallSocketServiceProvider.overrideWithValue(socket),
        ],
        child: const MaterialApp(
          home: ProviderInAppCallScreen(callId: 'call-1'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));

    expect(service.joinCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    service.response.complete(_session());
    await tester.pump();
  });
}

AppCallSession _session() => const AppCallSession(
      callId: 'call-1',
      bookingType: 'ride',
      bookingId: 'ride-1',
      roomName: 'room-1',
      status: 'connecting',
      callerId: 'client-1',
      callerRole: 'client',
      callerName: 'Client',
      calleeId: 'driver-1',
      calleeRole: 'driver',
      calleeName: 'Driver',
      createdAt: '2026-07-22T00:00:00.000Z',
      expiresAt: '2026-07-22T00:01:00.000Z',
      rtcProvider: 'webrtc',
    );
