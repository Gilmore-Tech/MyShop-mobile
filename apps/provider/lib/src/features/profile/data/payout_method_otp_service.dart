import 'package:dio/dio.dart';

/// Wraps the two payout-method OTP endpoints:
///   `POST /v1/payments/payout-method/request-otp`
///   `POST /v1/payments/payout-method/verify-otp`
///
/// Flow: the user enters a method + account number → the server stashes a
/// candidate keyed by their userId and SMS-sends a 6-digit code to that
/// number. The user types the code, the server commits the candidate to
/// `payoutMethod` + `payoutAccountNumber` and flips `payoutLocked = true`.
class PayoutMethodOtpService {
  PayoutMethodOtpService(this._dio);

  final Dio _dio;

  /// Request an OTP for the given (method, accountNumber). The server
  /// stashes the candidate (10-min TTL, 5 attempts) and SMS-sends a code.
  ///
  /// Re-issuing replaces any prior candidate. Cooldown is enforced
  /// server-side (60s between sends, 3 sends per hour).
  Future<PayoutOtpResult> requestOtp({
    required String method,
    required String accountNumber,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/payments/payout-method/request-otp',
        data: {
          'method': method,
          'accountNumber': accountNumber,
        },
      );
      final body = response.data ?? const <String, dynamic>{};
      if (body['success'] == true && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        return PayoutOtpResult(
          success: true,
          expiresAt: _parseDate(data['expiresAt']),
          retryAfterSeconds: (data['retryAfterSeconds'] as num?)?.toInt() ?? 60,
        );
      }
      return const PayoutOtpResult.failure(
        code: 'UNKNOWN',
        message: 'Could not send code. Please try again.',
      );
    } on DioException catch (e) {
      return _failureFromDio(e, isVerify: false);
    } catch (_) {
      return const PayoutOtpResult.failure(
        code: 'NETWORK',
        message: 'Connection lost — please try again.',
      );
    }
  }

  /// Verify the OTP. The body carries only the [code] — the candidate
  /// (method + account) is server-side, keyed by the authenticated user.
  /// On success, the server commits the candidate and locks the field.
  Future<PayoutOtpResult> verifyOtp({required String code}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/payments/payout-method/verify-otp',
        data: {'code': code},
      );
      final body = response.data ?? const <String, dynamic>{};
      if (body['success'] == true) {
        return const PayoutOtpResult(success: true);
      }
      return const PayoutOtpResult.failure(
        code: 'UNKNOWN',
        message: 'Verification failed. Please try again.',
      );
    } on DioException catch (e) {
      return _failureFromDio(e, isVerify: true);
    } catch (_) {
      return const PayoutOtpResult.failure(
        code: 'NETWORK',
        message: 'Connection lost — please try again.',
      );
    }
  }

  PayoutOtpResult _failureFromDio(DioException e, {required bool isVerify}) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      // The API's canonical error envelope is
      // {success:false,error:{code,message,details}}. Retain the old flat
      // fallback only for already-deployed servers during the update window.
      final nested = data['error'];
      final error =
          nested is Map<String, dynamic> ? nested : const <String, dynamic>{};
      final details = error['details'] is Map<String, dynamic>
          ? error['details'] as Map<String, dynamic>
          : data['details'] is Map<String, dynamic>
              ? data['details'] as Map<String, dynamic>
              : const <String, dynamic>{};
      final codeValue = error['code'] ??
          data['code'] ??
          data['errorCode'] ??
          (nested is String ? nested : null);
      final code =
          codeValue is String && codeValue.isNotEmpty ? codeValue : null;
      final messageValue = error['message'] ?? data['message'];
      final message =
          messageValue is String && messageValue != code ? messageValue : null;
      final retryAfter = (details['retryAfterSecs'] as num?)?.toInt() ??
          (details['retryAfterSeconds'] as num?)?.toInt() ??
          (data['retryAfterSeconds'] as num?)?.toInt();
      final otpActive = details['otpActive'] == true;
      if (code != null) {
        return PayoutOtpResult.failure(
          code: code,
          message: message ?? _messageFor(code, isVerify: isVerify),
          retryAfterSeconds: retryAfter,
          otpActive: otpActive,
        );
      }
    }
    return const PayoutOtpResult.failure(
      code: 'NETWORK',
      message: 'Connection lost — please try again.',
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}

/// Outcome of either OTP endpoint. On success, [expiresAt] +
/// [retryAfterSeconds] are populated for `requestOtp`. On failure, [code]
/// is the backend's machine-readable code (e.g. `OTP_INVALID`,
/// `OTP_RATE_LIMIT`) and [message] is user-facing copy. For
/// `OTP_RATE_LIMIT`, [retryAfterSeconds] tells the UI how long to disable
/// the resend button.
class PayoutOtpResult {
  const PayoutOtpResult({
    required this.success,
    this.code,
    this.message,
    this.expiresAt,
    this.retryAfterSeconds,
    this.otpActive = false,
  });

  const PayoutOtpResult.failure({
    required String code,
    String? message,
    int? retryAfterSeconds,
    bool otpActive = false,
  }) : this(
          success: false,
          code: code,
          message: message,
          retryAfterSeconds: retryAfterSeconds,
          otpActive: otpActive,
        );

  final bool success;
  final String? code;
  final String? message;
  final DateTime? expiresAt;
  final int? retryAfterSeconds;
  final bool otpActive;

  bool get isFailure => !success;
}

String _messageFor(String code, {required bool isVerify}) {
  switch (code) {
    case 'BANK_TRANSFER_NOT_SUPPORTED':
      return 'Bank transfers aren\'t supported yet — pick a MoMo wallet.';
    case 'ROLE_NOT_ALLOWED':
      return 'Only drivers and providers can set a payout method.';
    case 'PAYOUT_METHOD_LOCKED':
      return 'Your payout method is already verified. Contact support to '
          'change it.';
    case 'OTP_RATE_LIMIT':
    case 'OTP_DELIVERY_RATE_LIMITED':
      return 'Too many code requests. Please wait a moment and try again.';
    case 'OTP_DELIVERY_FAILED':
      return 'We could not confirm SMS delivery. If the code arrives, you can still enter it.';
    case 'OTP_CONTROL_UNAVAILABLE':
      return 'Code requests are temporarily unavailable. Please try again shortly.';
    case 'NO_PENDING_OTP':
      return 'No code to verify. Request a new one.';
    case 'OTP_EXPIRED':
      return 'That code has expired. Request a new one.';
    case 'OTP_INVALID':
      return 'Wrong code. Try again.';
    case 'OTP_ATTEMPTS_EXCEEDED':
      return 'Too many wrong attempts. Request a new code.';
    case 'NETWORK':
      return 'Connection lost — please try again.';
    default:
      return isVerify
          ? 'Verification failed. Please try again.'
          : 'Could not send code. Please try again.';
  }
}
