import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/local_notification_service.dart';

void main() {
  test('cold-start request action keeps its notification action id', () {
    final payload = decodeNotificationTapPayload(
      '{"type":"ride_request","rideId":"ride-1","offerId":"offer-1"}',
      actionId: NotificationPayload.actionRideAccept,
    );

    expect(payload, isNotNull);
    expect(
      payload![NotificationPayload.keyActionId],
      NotificationPayload.actionRideAccept,
    );
    expect(payload[NotificationPayload.keyRideId], 'ride-1');
  });

  test('notification body tap remains an actionless View payload', () {
    final payload = decodeNotificationTapPayload(
      '{"type":"ride_request","rideId":"ride-1"}',
    );

    expect(payload, isNotNull);
    expect(payload, isNot(contains(NotificationPayload.keyActionId)));
  });

  test('malformed launch payload is ignored', () {
    expect(decodeNotificationTapPayload('{not-json'), isNull);
  });
}
