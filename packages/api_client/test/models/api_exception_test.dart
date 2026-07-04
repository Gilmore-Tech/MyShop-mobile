import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('parses NestJS string error envelopes as ApiException errorCode', () {
    final exception = ApiException.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/auth/provider/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/provider/login'),
          statusCode: 409,
          data: const {
            'statusCode': 409,
            'error': 'ALREADY_LOGGED_IN_ELSEWHERE',
            'message': 'You are already logged in on another device.',
            'details': {
              'activeDevice': {'deviceInfo': 'Pixel 8'},
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(exception, isA<ConflictException>());
    expect(exception.errorCode, AuthErrorCodes.alreadyLoggedInElsewhere);
    expect(exception.message, 'You are already logged in on another device.');
    expect(exception.details?['activeDevice'], isA<Map<String, dynamic>>());
    expect(AuthErrorMapper.isAlreadyLoggedInElsewhere(exception), isTrue);
  });

  test('detects already-logged-in conflict from tolerant message fallback', () {
    const exception = ConflictException(
      message: 'User is already logged in elsewhere.',
    );

    expect(AuthErrorMapper.isAlreadyLoggedInElsewhere(exception), isTrue);
  });

  test('parses top-level errorCode when backend does not nest error object',
      () {
    final exception = ApiException.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/auth/login/client'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/login/client'),
          statusCode: 409,
          data: const {
            'statusCode': 409,
            'error': 'Conflict',
            'errorCode': 'ALREADY_LOGGED_IN_ELSEWHERE',
            'message': 'Active session already exists for this device role.',
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(exception, isA<ConflictException>());
    expect(exception.errorCode, AuthErrorCodes.alreadyLoggedInElsewhere);
    expect(AuthErrorMapper.isAlreadyLoggedInElsewhere(exception), isTrue);
  });
}
