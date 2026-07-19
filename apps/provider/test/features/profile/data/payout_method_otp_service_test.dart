import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/data/payout_method_otp_service.dart';

void main() {
  Dio rejectingDio(Map<String, dynamic> body, {int statusCode = 503}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: statusCode,
              data: body,
            ),
          ),
        ),
      ),
    );
    return dio;
  }

  test('parses the canonical nested API error and retry metadata', () async {
    final service = PayoutMethodOtpService(
      rejectingDio(
        {
          'success': false,
          'error': {
            'code': 'OTP_RATE_LIMIT',
            'message': 'Please wait before requesting another OTP.',
            'details': {'retryAfterSecs': 37},
          },
        },
        statusCode: 429,
      ),
    );

    final result = await service.requestOtp(
      method: 'momo_mtn',
      accountNumber: '0241234567',
    );

    expect(result.success, isFalse);
    expect(result.code, 'OTP_RATE_LIMIT');
    expect(result.message, 'Please wait before requesting another OTP.');
    expect(result.retryAfterSeconds, 37);
    expect(result.otpActive, isFalse);
  });

  test('preserves explicit active-code state after an uncertain send',
      () async {
    final service = PayoutMethodOtpService(
      rejectingDio({
        'success': false,
        'error': {
          'code': 'OTP_DELIVERY_FAILED',
          'message': 'We could not confirm SMS delivery.',
          'details': {
            'channel': 'sms',
            'retryAfterSecs': 60,
            'otpActive': true,
          },
        },
      }),
    );

    final result = await service.requestOtp(
      method: 'momo_mtn',
      accountNumber: '0241234567',
    );

    expect(result.code, 'OTP_DELIVERY_FAILED');
    expect(result.retryAfterSeconds, 60);
    expect(result.otpActive, isTrue);
  });

  test('retains the flat error fallback during the backend update window',
      () async {
    final service = PayoutMethodOtpService(
      rejectingDio({
        'error': 'PAYOUT_METHOD_LOCKED',
        'message': 'Contact support to change it.',
      }, statusCode: 409),
    );

    final result = await service.requestOtp(
      method: 'momo_mtn',
      accountNumber: '0241234567',
    );

    expect(result.code, 'PAYOUT_METHOD_LOCKED');
    expect(result.message, 'Contact support to change it.');
  });

  test('uses NETWORK only when no structured API error exists', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'offline',
          ),
        ),
      ),
    );

    final result = await PayoutMethodOtpService(dio).requestOtp(
      method: 'momo_mtn',
      accountNumber: '0241234567',
    );

    expect(result.code, 'NETWORK');
  });
}
