import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/live_activity_service.dart';

void main() {
  test('parses push-to-start token events', () {
    final event = liveActivityBridgeEventFromMap(const {
      'type': 'pushToStartToken',
      'token': 'push-token',
    });

    expect(event?.type, LiveActivityBridgeEventType.pushToStartToken);
    expect(event?.token, 'push-token');
  });

  test('normalises and parses per-activity update tokens', () {
    final event = liveActivityBridgeEventFromMap(const {
      'type': 'activityUpdateToken',
      'token': 'update-token',
      'activityId': 'activity-1',
      'requestType': 'ride_request',
      'requestId': '60d4cfb6-c198-453a-af51-c787624951a9',
      'offerId': '37cfe2f2-a5d2-4515-a1f5-330545ed2d5c',
      'expiresAt': '2026-07-15T12:00:45Z',
    });

    expect(event?.type, LiveActivityBridgeEventType.activityUpdateToken);
    expect(event?.activity?.requestType, 'ride');
    expect(event?.activity?.updateToken, 'update-token');
    expect(event?.activity?.expiresAt, DateTime.utc(2026, 7, 15, 12, 0, 45));
  });

  test('rejects malformed activity token events', () {
    expect(
      liveActivityBridgeEventFromMap(const {
        'type': 'activityUpdateToken',
        'token': 'update-token',
        'activityId': 'activity-1',
      }),
      isNull,
    );
    expect(normaliseLiveActivityRequestType('unknown'), isNull);
  });

  test('parses Live Activity authorization changes', () {
    final event = liveActivityBridgeEventFromMap(const {
      'type': 'activitiesEnabled',
      'enabled': false,
    });

    expect(event?.type, LiveActivityBridgeEventType.activitiesEnabled);
    expect(event?.activitiesEnabled, isFalse);
  });
}
