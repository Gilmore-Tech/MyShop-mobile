import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/utils/ride_destination_change_error.dart';

void main() {
  String messageFor(String code) => friendlyRideDestinationChangeError(
        ApiException(message: 'raw backend detail', errorCode: code),
      );

  test('maps the exact runtime-disable and service-area codes', () {
    expect(
      messageFor('RIDE_DESTINATION_EDIT_DISABLED'),
      contains('temporarily turned off'),
    );
    expect(
      messageFor('RIDE_DESTINATION_EDIT_CONFIG_UNAVAILABLE'),
      contains('pricing controls'),
    );
    expect(
      messageFor('OUTSIDE_PILOT_REGION'),
      contains('outside the active service area'),
    );
  });

  test('maps trusted-location and route-limit failures to next steps', () {
    expect(
      messageFor('RIDE_DESTINATION_REPRICE_LOCATION_STALE'),
      contains('try the drop-off change again'),
    );
    expect(
      messageFor('RIDE_DESTINATION_REPRICE_TRAIL_UNTRUSTED'),
      contains('verified driving history'),
    );
    expect(
      messageFor('RIDE_DESTINATION_CHANGE_TOO_LARGE'),
      contains('Choose a closer destination'),
    );
  });

  test('invalidates every exact backend preview and route revision code', () {
    const codes = {
      'RIDE_DESTINATION_PREVIEW_EXPIRED',
      'RIDE_DESTINATION_PREVIEW_INVALID',
      'RIDE_DESTINATION_PREVIEW_REVISION_MISMATCH',
      'RIDE_DESTINATION_PREVIEW_STALE',
      'RIDE_DESTINATION_PREVIEW_USED',
      'RIDE_DESTINATION_LIMIT_CHANGED',
      'RIDE_ROUTE_REVISION_CHANGED',
      'RIDE_ROUTE_CHANGED',
      'RIDE_QUOTE_CHANGED',
    };

    for (final code in codes) {
      expect(destinationPreviewNoLongerUsable(code), isTrue, reason: code);
      expect(messageFor(code), isNot(contains('raw backend detail')),
          reason: code);
    }
    expect(destinationPreviewNoLongerUsable('SOME_OTHER_ERROR'), isFalse);
    expect(
      messageFor('RIDE_QUOTE_CHANGED'),
      contains('route changed'),
    );
  });

  test('discards previews after terminal ride and payment boundaries', () {
    const codes = {
      'RIDE_DESTINATION_NOT_EDITABLE',
      'RIDE_DESTINATION_CHANGE_NOT_ALLOWED',
      'RIDE_COMPLETION_ALREADY_STARTED',
      'RIDE_PAYMENT_ALREADY_EXISTS',
      'RIDE_HAS_QUEUED_SUCCESSOR',
      'INVALID_STATUS_TRANSITION',
      'RIDE_NOT_ACTIVE',
    };

    for (final code in codes) {
      expect(destinationPreviewNoLongerUsable(code), isTrue, reason: code);
    }
  });

  test('maps payment, loyalty and toll safety blocks without raw copy', () {
    expect(
        messageFor('RIDE_PAYMENT_ALREADY_EXISTS'), contains('being completed'));
    expect(
      messageFor('RIDE_DESTINATION_LOYALTY_REFUND_REQUIRED'),
      contains('redeemed points'),
    );
    expect(
      messageFor('RIDE_TOLL_REPRICE_UNAVAILABLE'),
      contains('toll could not be verified'),
    );
  });
}
