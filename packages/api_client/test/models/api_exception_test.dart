import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('unknown trusted-service failures do not blame user connectivity', () {
    const exception = NetworkException(
      message: 'malformed upstream detail',
      kind: NetworkFailureKind.unavailable,
    );

    expect(
      AuthErrorMapper.message(exception),
      'Service temporarily unavailable. Please try again in a moment.',
    );
    expect(AuthErrorMapper.message(exception), isNot(contains('network')));
    expect(AuthErrorMapper.message(exception), isNot(contains('internet')));
  });

  test('unknown auth errors never expose backend prose', () {
    const exception = ApiException(
      message: 'SQLSTATE 23505 internal_auth_identity_phone_key',
      statusCode: 400,
      errorCode: 'UNRECOGNISED_AUTH_FAILURE',
    );

    final message = AuthErrorMapper.message(exception);

    expect(message, 'Something went wrong. Please try again.');
    expect(message, isNot(contains('SQLSTATE')));
  });

  test('auth validation details are converted to app-owned field copy', () {
    const exception = ValidationException(
      message: 'phone must match private validator /prod-v2',
      errorCode: 'VALIDATION_ERROR',
      details: <String, dynamic>{
        'phone': <String>['phone must match private validator /prod-v2'],
        'internalField': <String>['database rule details'],
      },
    );

    final fields = AuthErrorMapper.fieldErrors(exception);

    expect(fields['phone'], 'Enter a valid 9-digit Ghana phone number.');
    expect(fields['internalField'], 'Check this field and try again.');
    expect(AuthErrorMapper.message(exception), fields['phone']);
  });

  test('auth field errors ignore support and validation metadata', () {
    const exception = ValidationException(
      message: 'Validation failed',
      errorCode: 'VALIDATION_ERROR',
      details: <String, dynamic>{
        'supportReference': '15286d11-fceb-43e6-ac0e-41f96d9a1b77',
        'validation': <String>['private validator detail'],
      },
    );

    expect(AuthErrorMapper.fieldErrors(exception), isEmpty);
    expect(
      AuthErrorMapper.message(exception),
      'Check the information you entered and try again.',
    );
  });

  test(
      'canonical validation envelope cannot turn its support UUID into field copy',
      () {
    final exception = ApiException.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/register'),
          statusCode: 400,
          data: const {
            'success': false,
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Validation failed',
              'details': {
                'validation': <String>['private class-validator detail'],
              },
              'supportReference': 'cf539e20-e5a6-4e8c-a281-da24848bd75a',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(AuthErrorMapper.fieldErrors(exception), isEmpty);
    final message = AuthErrorMapper.message(exception);
    expect(message, 'Check the information you entered and try again.');
    expect(message, isNot(contains('cf539e20')));
    expect(message, isNot(contains('class-validator')));
  });

  test('personal-name validation fields use the approved safe copy', () {
    const exception = ValidationException(
      message: 'private name validator details',
      errorCode: 'VALIDATION_ERROR',
      details: <String, dynamic>{
        'fullName': <String>['must satisfy internal rule'],
        'displayName': <String>['must satisfy internal rule'],
        'legalName': <String>['must satisfy internal rule'],
      },
    );
    const expected =
        'Names cannot contain numbers or emojis. Use letters, spaces, hyphens, and apostrophes only.';

    final fields = AuthErrorMapper.fieldErrors(exception);

    expect(fields['fullName'], expected);
    expect(fields['displayName'], expected);
    expect(fields['legalName'], expected);
    expect(AuthErrorMapper.message(exception), expected);
  });

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
              'recoveryChallenge': 'opaque-recovery-challenge-1234567890',
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
    expect(
      AuthErrorMapper.sessionRecoveryChallenge(exception),
      'opaque-recovery-challenge-1234567890',
    );
  });

  test('rejects malformed recovery capabilities from error details', () {
    const exception = ConflictException(
      message: 'Already signed in.',
      errorCode: AuthErrorCodes.alreadyLoggedInElsewhere,
      details: {'recoveryChallenge': 'too-short'},
    );

    expect(AuthErrorMapper.sessionRecoveryChallenge(exception), isNull);
  });

  test('detects already-logged-in conflict from tolerant message fallback', () {
    const exception = ConflictException(
      message: 'User is already logged in elsewhere.',
    );

    expect(AuthErrorMapper.isAlreadyLoggedInElsewhere(exception), isTrue);
  });

  test(
    'parses top-level errorCode when backend does not nest error object',
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
    },
  );

  test('preserves active-OTP details on 503 delivery failure', () {
    final exception = ApiException.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/auth/login/client'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/login/client'),
          statusCode: 503,
          data: const {
            'statusCode': 503,
            'error': 'OTP_DELIVERY_FAILED',
            'message': 'Carrier detail that must not reach the UI.',
            'details': {
              'channel': 'sms',
              'retryAfterSecs': null,
              'otpActive': true,
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(exception, isA<ServerException>());
    expect(exception.errorCode, 'OTP_DELIVERY_FAILED');
    expect(exception.details?['otpActive'], isTrue);
    expect(AuthErrorMapper.hasActiveOtp(exception), isTrue);
    expect(
      AuthErrorMapper.message(exception),
      'We couldn\'t confirm SMS delivery. Your code is still active. '
      'Wait for it or use resend.',
    );
  });

  test('parses canonical active-OTP 429 without exposing diagnostics', () {
    final exception = ApiException.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/register'),
          statusCode: 429,
          data: const {
            'success': false,
            'error': {
              'code': 'RATE_LIMIT_EXCEEDED',
              'message': 'Backend wording must stay hidden.',
              'details': {'otpActive': true},
              'supportReference': '15286d11-fceb-43e6-ac0e-41f96d9a1b77',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(exception.statusCode, 429);
    expect(exception.errorCode, 'RATE_LIMIT_EXCEEDED');
    expect(exception.details?['otpActive'], isTrue);
    expect(
      exception.details?['supportReference'],
      '15286d11-fceb-43e6-ac0e-41f96d9a1b77',
    );
    expect(AuthErrorMapper.hasActiveOtp(exception), isTrue);
    final message = AuthErrorMapper.message(exception);
    expect(message, contains('code is still active'));
    expect(message, isNot(contains('RATE_LIMIT_EXCEEDED')));
    expect(message, isNot(contains('Backend wording')));
    expect(message, isNot(contains('15286d11')));
  });

  test('never infers an active OTP from a 429 or truthy string', () {
    const cooldown = ApiException(
      message: 'Please wait.',
      statusCode: 429,
      errorCode: 'OTP_COOLDOWN',
      details: {'retryAfterSecs': 18},
    );
    const malformedDelivery = ApiException(
      message: 'Failed.',
      statusCode: 503,
      errorCode: 'OTP_DELIVERY_FAILED',
      details: {'otpActive': 'true'},
    );

    expect(AuthErrorMapper.hasActiveOtp(cooldown), isFalse);
    expect(AuthErrorMapper.hasActiveOtp(malformedDelivery), isFalse);
    expect(
      AuthErrorMapper.message(cooldown),
      'Please wait before requesting another code.',
    );
  });

  test('maps only the stable retained-role code to recovery support', () {
    const retained = ApiException(
      message: 'backend detail must not be shown',
      statusCode: 409,
      errorCode: AuthErrorCodes.roleAccountRetained,
    );
    const duplicate = ApiException(
      message: 'contact support maybe',
      statusCode: 409,
      errorCode: 'DRIVER_ACCOUNT_EXISTS',
    );

    expect(AuthErrorMapper.requiresRoleRecoverySupport(retained), isTrue);
    expect(AuthErrorMapper.requiresRoleRecoverySupport(duplicate), isFalse);
    expect(
      AuthErrorMapper.message(retained),
      'This role was previously deleted and cannot be registered again. '
      'Contact support if you want to request recovery.',
    );
  });

  test('maps resend quota and provider channel errors to safe app copy', () {
    const resendLimit = ApiException(
      message: 'raw resend response',
      statusCode: 400,
      errorCode: 'OTP_RESEND_LIMIT',
    );
    const channelUnavailable = ServerException(
      message: 'credential detail',
      statusCode: 503,
      errorCode: 'CHANNEL_UNAVAILABLE',
    );

    expect(
      AuthErrorMapper.message(resendLimit),
      'You\'ve reached the resend limit for this code. Enter the current '
      'code or go back and request a new one later.',
    );
    expect(
      AuthErrorMapper.message(channelUnavailable),
      'That delivery option is unavailable. Please try another channel.',
    );
  });

  test('expired OTP tells the user to request rather than resend a code', () {
    const expired = UnauthorizedException(
      message: 'raw expired response',
      errorCode: 'OTP_EXPIRED',
    );

    expect(
      AuthErrorMapper.message(expired),
      'This code has expired. Go back and request a new code.',
    );
  });

  test(
    'maps Redis-authority failures without exposing infrastructure details',
    () {
      const verificationUnavailable = ServerException(
        message: 'redis://user:secret@example.invalid',
        statusCode: 503,
        errorCode: 'OTP_VERIFICATION_CONTROL_UNAVAILABLE',
      );

      expect(
        AuthErrorMapper.message(verificationUnavailable),
        'Code verification is temporarily unavailable. Please try again shortly.',
      );
    },
  );

  test('preserves only machine-readable provider eligibility reason codes', () {
    final exception = ApiException.fromDioException(
      DioException(
        requestOptions: RequestOptions(path: '/location/driver/update'),
        response: Response(
          requestOptions: RequestOptions(path: '/location/driver/update'),
          statusCode: 403,
          data: const {
            'statusCode': 403,
            'error': 'PROVIDER_NOT_ELIGIBLE',
            'message': 'Internal eligibility detail.',
            'reasonCodes': [
              'DOCUMENT_EXPIRED_DRIVERS_LICENCE',
              'DOCUMENT_EXPIRED_DRIVERS_LICENCE',
              'not a machine code',
              42,
            ],
            'details': {'correlationId': 'safe-test-id'},
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(exception.errorCode, 'PROVIDER_NOT_ELIGIBLE');
    expect(exception.details?['correlationId'], 'safe-test-id');
    expect(exception.details?['reasonCodes'], [
      'DOCUMENT_EXPIRED_DRIVERS_LICENCE',
    ]);
  });
}
