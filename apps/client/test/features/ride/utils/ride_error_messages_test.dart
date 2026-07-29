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

  test('maps no-driver result to availability copy before server fallback', () {
    const error = ServerException(
      message: 'Internal provider failure text',
      statusCode: 503,
      errorCode: 'NO_DRIVERS_AVAILABLE',
    );

    expect(rideRequestErrorMessage(error), noDriversAvailableMessage);
    expect(
      rideRequestErrorMessage(error),
      'All nearby drivers are busy or offline. Please try again.',
    );
  });

  test('keeps genuine server failures distinct from no-driver results', () {
    const error = ServerException(
      message: 'Internal provider failure text',
      statusCode: 503,
      errorCode: 'DEPENDENCY_UNAVAILABLE',
    );

    expect(
      rideRequestErrorMessage(error),
      'Service temporarily unavailable. Please try again in a moment.',
    );
  });

  test('socket cancellation never renders free-form server prose', () {
    final message = rideSocketCancellationMessage(
      reason: 'SQLSTATE 23505: customer_phone_idx',
      cancelledBy: 'unknown_actor',
    );

    expect(message, 'This ride was cancelled.');
    expect(message, isNot(contains('SQLSTATE')));
  });

  test('socket cancellation maps only known actor and no-driver fields', () {
    expect(
      rideSocketCancellationMessage(
        reason: 'driver_cancelled',
        cancelledBy: 'driver',
      ),
      'The driver cancelled this ride.',
    );
    expect(
      rideSocketCancellationMessage(
        reason: 'no_drivers_available',
        cancelledBy: 'system',
      ),
      noDriversAvailableMessage,
    );
    expect(
      rideSocketDriverDelayMessage,
      'Your driver is delayed, but the ride is still active.',
    );
  });

  test('system initialization timeout is not mislabeled as no drivers', () {
    final message = rideSocketCancellationMessage(
      reason: 'initialization_timeout',
      cancelledBy: 'system',
    );

    expect(
      message,
      "We couldn't finish requesting your ride. Please try again.",
    );
    expect(message, isNot(noDriversAvailableMessage));
  });

  test('uses fixed copy for every authoritative cancellation actor', () {
    expect(
      rideSocketCancellationMessage(cancelledBy: 'client'),
      'You cancelled this ride.',
    );
    expect(
      rideSocketCancellationMessage(cancelledBy: 'driver'),
      'The driver cancelled this ride.',
    );
    expect(
      rideSocketCancellationMessage(cancelledBy: 'admin'),
      'MyShop support cancelled this ride.',
    );
    expect(
      rideSocketCancellationMessage(
        reason: 'private_backend_reason',
        cancelledBy: 'system',
      ),
      'MyShop ended this ride because it could not continue.',
    );
  });

  test('does not classify every system cancellation as no drivers', () {
    expect(
      isNoDriversSocketCancellation(
        status: 'cancelled',
        reason: 'initialization_timeout',
      ),
      isFalse,
    );
    expect(
      isNoDriversSocketCancellation(
        status: 'cancelled',
        reason: 'no_drivers_available',
      ),
      isTrue,
    );
  });
}
