import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:incoming_request_overlay/incoming_request_overlay.dart';
import 'package:myshop_provider/src/core/services/incoming_request_action_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('com.gilmoretech.myshop/request_action');
  const androidMethodChannel = MethodChannel(
    'com.gilmoretech.myshop/test_request_action_methods',
  );
  const androidEventChannel = EventChannel(
    'com.gilmoretech.myshop/test_request_action_events',
  );
  late List<MethodCall> nativeCalls;
  late List<MethodCall> androidNativeCalls;

  setUp(() {
    nativeCalls = <MethodCall>[];
    androidNativeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      nativeCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidMethodChannel, (call) async {
      androidNativeCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidMethodChannel, null);
  });

  Map<String, dynamic> action(String actionId) => <String, dynamic>{
        'actionId': actionId,
        'action': 'ride_view',
        'rideId': 'ride-1',
        'requestType': 'ride_request',
      };

  test(
    'suppresses a completed iOS action replayed by the pending snapshot',
    () async {
      var handled = 0;
      final bridge = IncomingRequestActionBridge(
        handleAction: (_) async => handled += 1,
      );

      await bridge.processIosActionForTesting(action('action-1'));
      await bridge.processIosActionForTesting(action('action-1'));

      expect(handled, 1);
      expect(
        nativeCalls.where((call) => call.method == 'acknowledgeRequestAction'),
        hasLength(1),
      );
    },
  );

  test(
    'suppresses EventChannel and pending-snapshot race for one action',
    () async {
      var handled = 0;
      final handlerEntered = Completer<void>();
      final releaseHandler = Completer<void>();
      final bridge = IncomingRequestActionBridge(
        handleAction: (_) async {
          handled += 1;
          handlerEntered.complete();
          await releaseHandler.future;
        },
      );

      final eventDelivery = bridge.processIosActionForTesting(
        action('action-race'),
      );
      await handlerEntered.future;
      final pendingReplay = bridge.processIosActionForTesting(
        action('action-race'),
      );
      await pendingReplay;
      releaseHandler.complete();
      await eventDelivery;

      // A stale copy from the startup snapshot can be iterated after the event
      // handler has completed. It must remain idempotently suppressed.
      await bridge.processIosActionForTesting(action('action-race'));

      expect(handled, 1);
      expect(
        nativeCalls.where((call) => call.method == 'acknowledgeRequestAction'),
        hasLength(1),
      );
    },
  );

  test(
    'suppresses a completed Android action replayed by a stale snapshot',
    () async {
      var handled = 0;
      final overlay = IncomingRequestOverlay.withChannels(
        methodChannel: androidMethodChannel,
        eventChannel: androidEventChannel,
      );
      final bridge = IncomingRequestActionBridge(
        androidOverlay: overlay,
        handleAction: (_) async => handled += 1,
      );
      final event = IncomingRequestOverlayAction(
        actionId: 'android-action-1',
        action: IncomingRequestActionType.rideView,
        offerId: 'offer-1',
        offerType: IncomingRequestOfferType.ride,
        occurredAt: DateTime.utc(2026, 7, 30),
        payload: const {'rideId': 'ride-1'},
      );

      await bridge.processAndroidActionForTesting(event);
      await bridge.processAndroidActionForTesting(event);

      expect(handled, 1);
      expect(
        androidNativeCalls.where((call) => call.method == 'acknowledgeAction'),
        hasLength(1),
      );
    },
  );
}
