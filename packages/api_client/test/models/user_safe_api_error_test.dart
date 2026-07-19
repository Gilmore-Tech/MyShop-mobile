import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown backend prose is never returned', () {
    const error = ApiException(
      message: 'SQLSTATE 23505 on internal_customer_phone_idx',
      statusCode: 400,
      errorCode: 'UNRECOGNISED_INTERNAL_FAILURE',
    );

    final message = userSafeApiErrorMessage(
      error,
      fallback: 'The action failed. Please try again.',
    );

    expect(message, 'The action failed. Please try again.');
    expect(message, isNot(contains('SQLSTATE')));
  });

  test('network and server failures use stable copy', () {
    expect(
      userSafeApiErrorMessage(
        const NetworkException(message: 'socket host and port details'),
        fallback: 'fallback',
      ),
      'No internet connection. Check your network and try again.',
    );
    expect(
      userSafeApiErrorMessage(
        const ServerException(
          message: 'upstream stack trace',
          statusCode: 503,
        ),
        fallback: 'fallback',
      ),
      'Our servers are having trouble. Please try again in a moment.',
    );
  });

  test('status families can use feature-specific safe copy', () {
    expect(
      userSafeApiErrorMessage(
        const ApiException(message: 'raw', statusCode: 404),
        fallback: 'fallback',
        notFoundMessage: 'This ride is no longer available.',
      ),
      'This ride is no longer available.',
    );
    expect(
      userSafeApiErrorMessage(
        const ApiException(message: 'raw', statusCode: 409),
        fallback: 'fallback',
        conflictMessage: 'Refresh this job before trying again.',
      ),
      'Refresh this job before trying again.',
    );
  });

  test('rate limits are stable even when the backend code is unknown to UI',
      () {
    expect(
      userSafeApiErrorMessage(
        const ApiException(
          message: 'gateway quota key abc',
          statusCode: 429,
        ),
        fallback: 'fallback',
      ),
      'Too many attempts. Wait a moment, then try again.',
    );
  });
}
