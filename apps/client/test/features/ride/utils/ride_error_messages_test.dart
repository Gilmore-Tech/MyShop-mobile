import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/utils/ride_error_messages.dart';

void main() {
  test('maps outside pilot region estimate failure to clear rider copy', () {
    const error = ApiException(
      message:
          'Pickup and dropoff must both be within the Ashanti pilot region',
      statusCode: 400,
      errorCode: 'OUTSIDE_PILOT_REGION',
    );

    final copy = rideEstimateErrorCopy(error);

    expect(copy.title, 'Outside service area');
    expect(copy.message, contains('Kumasi/Ashanti'));
    expect(copy.showRetry, isFalse);
  });

  test('keeps retry action for generic estimate failures', () {
    const error = ApiException(
      message: 'Something went wrong. Please try again.',
      statusCode: 500,
    );

    final copy = rideEstimateErrorCopy(error);

    expect(copy.title, 'Could not load fare estimate');
    expect(copy.showRetry, isTrue);
  });
}
