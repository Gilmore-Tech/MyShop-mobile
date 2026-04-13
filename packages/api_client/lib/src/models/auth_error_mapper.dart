import 'api_exception.dart';

/// Maps [ApiException] instances to user-friendly, actionable error messages
/// for the auth flow (register, login, OTP verification).
///
/// Falls back to the backend message if the error code is unrecognised.
class AuthErrorMapper {
  AuthErrorMapper._();

  /// Returns a user-facing message for auth-related API errors.
  static String message(Object error) {
    if (error is NetworkException) {
      return _networkMessage(error);
    }
    if (error is ApiException) {
      return _apiMessage(error);
    }
    return 'Something went wrong. Please try again.';
  }

  /// Extracts per-field validation messages from a [ValidationException].
  /// Returns a map of field name → error message, or empty if unavailable.
  static Map<String, String> fieldErrors(Object error) {
    if (error is! ApiException || error.details == null) {
      return const {};
    }
    final result = <String, String>{};
    for (final entry in error.details!.entries) {
      if (entry.value is String) {
        result[entry.key] = entry.value as String;
      } else if (entry.value is List && (entry.value as List).isNotEmpty) {
        // NestJS validation returns arrays: { "phone": ["must be a string"] }
        result[entry.key] = (entry.value as List).first.toString();
      }
    }
    return result;
  }

  static String _networkMessage(NetworkException e) {
    if (e.message.contains('timed out')) {
      return 'Connection timed out. Check your internet and try again.';
    }
    return 'No internet connection. Check your network and try again.';
  }

  static String _apiMessage(ApiException e) {
    // Map known error codes to actionable messages.
    switch (e.errorCode) {
      // ── Registration ────────────────────────────────────────────────
      case 'PHONE_ALREADY_REGISTERED':
      case 'USER_ALREADY_EXISTS':
        return 'This phone number is already registered. Try signing in instead.';

      case 'INVALID_PHONE':
      case 'INVALID_PHONE_FORMAT':
        return 'This phone number isn\'t valid. Enter a 9-digit Ghana number.';

      case 'REGISTRATION_DISABLED':
        return 'New sign-ups are temporarily paused. Please try again later.';

      // ── Login ───────────────────────────────────────────────────────
      case 'USER_NOT_FOUND':
      case 'PHONE_NOT_FOUND':
      case 'ACCOUNT_NOT_FOUND':
        return 'No account found with this number. Sign up to get started.';

      case 'ACCOUNT_SUSPENDED':
      case 'USER_SUSPENDED':
        return 'Your account has been suspended. Contact support for help.';

      case 'ACCOUNT_DEACTIVATED':
      case 'USER_DEACTIVATED':
        return 'Your account has been deactivated. Contact support to reactivate.';

      // ── OTP ─────────────────────────────────────────────────────────
      case 'INVALID_OTP':
      case 'OTP_INVALID':
        return 'Incorrect code. Check the SMS and try again.';

      case 'OTP_EXPIRED':
      case 'EXPIRED_OTP':
        return 'This code has expired. Tap "Resend code" to get a new one.';

      case 'OTP_MAX_ATTEMPTS':
      case 'TOO_MANY_OTP_ATTEMPTS':
        return 'Too many incorrect attempts. Wait a moment, then resend a new code.';

      case 'OTP_SEND_FAILED':
        return 'We couldn\'t send the code. Check your phone number and try again.';

      case 'OTP_RATE_LIMITED':
      case 'RATE_LIMITED':
      case 'TOO_MANY_REQUESTS':
        return 'Too many requests. Please wait a moment before trying again.';

      // ── Validation (422) ────────────────────────────────────────────
      case 'VALIDATION_ERROR':
      case 'VALIDATION_FAILED':
        return _validationSummary(e);

      // ── Server ──────────────────────────────────────────────────────
      case 'INTERNAL_ERROR':
      case 'SERVER_ERROR':
        return 'Our servers are having trouble. Please try again in a moment.';

      default:
        // Fall back to backend message if it's non-empty and not generic.
        if (e.message.isNotEmpty &&
            e.message != 'Something went wrong. Please try again.') {
          return e.message;
        }

        // Last resort based on status code.
        if (e.isServerError) {
          return 'Our servers are having trouble. Please try again in a moment.';
        }
        if (e.statusCode == 429) {
          return 'Too many requests. Please wait a moment before trying again.';
        }
        return 'Something went wrong. Please try again.';
    }
  }

  /// Builds a user-readable summary from validation error details.
  static String _validationSummary(ApiException e) {
    final fields = fieldErrors(e);
    if (fields.isEmpty) return e.message;
    // Show the first field error as the main message.
    return fields.values.first;
  }
}
