import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
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

  test(
    'offline, timeout, unknown transport and 5xx use distinct safe copy',
    () {
      expect(
        userSafeApiErrorMessage(
          const NetworkException(
            message: 'socket host and port details',
            kind: NetworkFailureKind.offline,
          ),
          fallback: 'fallback',
        ),
        'No internet connection. Check your network and try again.',
      );
      expect(
        userSafeApiErrorMessage(
          const NetworkException(
            message: 'upstream timing metadata',
            kind: NetworkFailureKind.timeout,
          ),
          fallback: 'fallback',
        ),
        'The connection timed out. Check your network and try again.',
      );
      expect(
        userSafeApiErrorMessage(
          const NetworkException(message: 'malformed transport detail'),
          fallback: 'fallback',
        ),
        'Service temporarily unavailable. Please try again in a moment.',
      );
      expect(
        userSafeApiErrorMessage(
          const ServerException(
            message: 'upstream stack trace',
            statusCode: 503,
          ),
          fallback: 'fallback',
        ),
        'Service temporarily unavailable. Please try again in a moment.',
      );
    },
  );

  test('401/403/404/409/422 use stable or feature-owned copy', () {
    expect(
      userSafeApiErrorMessage(
        const ApiException(message: 'raw', statusCode: 401),
        fallback: 'fallback',
      ),
      'Your session expired. Sign in again, then retry.',
    );
    expect(
      userSafeApiErrorMessage(
        const ApiException(message: 'raw', statusCode: 403),
        fallback: 'fallback',
      ),
      "This account isn't allowed to perform that action.",
    );
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
    expect(
      userSafeApiErrorMessage(
        const ApiException(message: 'raw', statusCode: 422),
        fallback: 'fallback',
      ),
      'Check the information you entered and try again.',
    );
  });

  test(
    'rate limits are stable even when the backend code is unknown to UI',
    () {
      expect(
        userSafeApiErrorMessage(
          const ApiException(message: 'gateway quota key abc', statusCode: 429),
          fallback: 'fallback',
        ),
        'Too many attempts. Wait a moment, then try again.',
      );
    },
  );

  test(
    'cancelled, stale and missing-auth states are never labelled offline',
    () {
      for (final code in const [
        'REQUEST_CANCELLED',
        'STALE_REQUEST',
        'MISSING_AUTH',
      ]) {
        final message = userSafeApiErrorMessage(
          ApiException(
            message: 'malicious backend prose for $code',
            errorCode: code,
          ),
          fallback: 'The action could not be completed. Please try again.',
        );
        expect(message, 'The action could not be completed. Please try again.');
        expect(message, isNot(contains('internet')));
        expect(message, isNot(contains('malicious')));
      }
    },
  );

  test('Dio cancellation is not converted into a network exception', () {
    final error = ApiException.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/cancelled'),
        type: DioExceptionType.cancel,
      ),
    );

    expect(error, isNot(isA<NetworkException>()));
    expect(error.errorCode, 'REQUEST_CANCELLED');
    expect(
      userSafeApiErrorMessage(error, fallback: 'The action was cancelled.'),
      'The action was cancelled.',
    );
  });
}
