import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:incoming_request_overlay/incoming_request_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('overlay-test-methods');
  const eventChannel = EventChannel('overlay-test-events');
  late IncomingRequestOverlay overlay;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    overlay = IncomingRequestOverlay.withChannels(
      methodChannel: methodChannel,
      eventChannel: eventChannel,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isSupported' || 'canDrawOverlays' || 'openOverlaySettings' => true,
        'showOffer' => true,
        'drainPendingActions' => <Object?>[
            <String, Object?>{
              'actionId': 'native-action-1',
              'action': 'ride_accept',
              'offerId': 'ride-1',
              'offerType': 'ride',
              'occurredAtMillis': 1710000000000,
              'payload': <String, String>{'requestToken': 'token-1'},
            },
          ],
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('showOffer sends an absolute deadline and display payload', () async {
    final deadline = DateTime.utc(2099, 7, 14, 12, 30);
    final shown = await overlay.showOffer(
      IncomingRequestOffer(
        offerId: 'ride-1',
        type: IncomingRequestOfferType.ride,
        expiresAt: deadline,
        title: 'New ride request',
        amount: 'GHS 50.00',
        amountLabel: 'EST. FULL FARE',
        pricingSummary: 'PROMO / DISCOUNT - GHS 8.00\nCLIENT PRICE GHS 42.00',
        duration: '18 min',
        pickup: 'Osu',
        destination: 'Airport',
        mapPreviewUrl: 'https://api.example.com/v1/offers/map/token',
        payload: const <String, String>{'rideId': 'ride-1'},
      ),
    );

    expect(shown, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'showOffer');
    final arguments = Map<Object?, Object?>.from(calls.single.arguments as Map);
    expect(arguments['offerId'], 'ride-1');
    expect(arguments['offerType'], 'ride');
    expect(arguments['expiresAtMillis'], deadline.millisecondsSinceEpoch);
    expect(arguments['pickup'], 'Osu');
    expect(arguments['duration'], '18 min');
    expect(arguments['amountLabel'], 'EST. FULL FARE');
    expect(
      arguments['pricingSummary'],
      'PROMO / DISCOUNT - GHS 8.00\nCLIENT PRICE GHS 42.00',
    );
    expect(
      arguments['mapPreviewUrl'],
      'https://api.example.com/v1/offers/map/token',
    );
    expect(arguments['payload'], <String, String>{'rideId': 'ride-1'});
  });

  test('expired offers never invoke the native service', () async {
    final shown = await overlay.showOffer(
      IncomingRequestOffer(
        offerId: 'job-1',
        type: IncomingRequestOfferType.job,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        title: 'New job request',
      ),
    );

    expect(shown, isFalse);
    expect(calls, isEmpty);
  });

  test('drainPendingActions parses durable native actions', () async {
    final actions = await overlay.drainPendingActions();

    expect(actions, hasLength(1));
    expect(actions.single.actionId, 'native-action-1');
    expect(actions.single.action, IncomingRequestActionType.rideAccept);
    expect(actions.single.offerType, IncomingRequestOfferType.ride);
    expect(actions.single.offerId, 'ride-1');
    expect(actions.single.payload['requestToken'], 'token-1');
    expect(actions.single.occurredAt.isUtc, isTrue);
  });

  test('dismissOffer uses deterministic type and id identity', () async {
    await overlay.dismissOffer(
      type: IncomingRequestOfferType.job,
      offerId: 'job-42',
    );

    expect(calls.single.method, 'dismissOffer');
    expect(calls.single.arguments, <String, Object>{
      'offerId': 'job-42',
      'offerType': 'job',
    });
  });

  test('unknown future native action remains parseable', () {
    final action = IncomingRequestOverlayAction.fromMap(<Object?, Object?>{
      'actionId': 'native-action-2',
      'action': 'future_action',
      'offerId': 'job-1',
      'offerType': 'job',
      'occurredAtMillis': 1710000000000,
    });

    expect(action.action, IncomingRequestActionType.unknown);
  });

  test('acknowledgeAction removes a handled native queue item', () async {
    await overlay.acknowledgeAction('native-action-1');

    expect(calls.single.method, 'acknowledgeAction');
    expect(calls.single.arguments, <String, String>{
      'actionId': 'native-action-1',
    });
  });
}
