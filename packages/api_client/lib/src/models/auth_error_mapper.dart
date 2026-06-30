import 'api_exception.dart';

/// Backend error codes that the mobile app reacts to programmatically
/// (not just for user-facing messages). Centralised here so the
/// interceptor, controllers, and mapper agree on the spelling.
class AuthErrorCodes {
  AuthErrorCodes._();

  /// Returned by /auth/login/* (409) when the same user has an active
  /// session on a different device. The app prompts the user to confirm
  /// the take-over and retries the login with `forceLogin: true`.
  static const alreadyLoggedInElsewhere = 'ALREADY_LOGGED_IN_ELSEWHERE';

  /// Returned on protected requests (401) when the current session was
  /// invalidated by another device taking over. Trigger a soft logout —
  /// clear the JWT pair and route to login, but preserve cached identity
  /// (phone, role, profile) so re-login is one-tap.
  static const sessionTakenOver = 'SESSION_TAKEN_OVER';

  /// Returned (401) when the access token's signature is valid but the
  /// expiry has passed. Refresh attempt should follow.
  static const tokenExpired = 'TOKEN_EXPIRED';

  /// Returned (401) for malformed/forged tokens. Treated as terminal —
  /// clears tokens and forces a fresh login.
  static const invalidToken = 'INVALID_TOKEN';

  /// Returned by /auth/refresh (401) when the supplied refresh token has
  /// already been consumed (rotation reuse detection). Always terminal —
  /// the entire token chain is suspect.
  static const refreshTokenReused = 'REFRESH_TOKEN_REUSED';

  /// Returned by /auth/refresh (401) when another concurrent refresh is
  /// in flight for the same (userId, role) pair. The backend lock admits
  /// one refresh at a time — losing parallel calls receive this code.
  /// NOT terminal: the caller should briefly back off and retry, by which
  /// point the winning refresh has rotated the token pair and the
  /// stored access token is fresh.
  static const refreshInFlight = 'REFRESH_IN_FLIGHT';

  /// Returned by /auth/verify-otp (400) during provider signup when the
  /// `regionId` carried by the earlier register call is unknown/inactive —
  /// practically only a stale-cache edge case. The app re-fetches
  /// `GET /v1/regions`, asks the user to re-select, and retries.
  static const invalidRegion = 'INVALID_REGION';
}

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

      // ── Multi-device session ────────────────────────────────────────
      case AuthErrorCodes.alreadyLoggedInElsewhere:
        return 'You\'re already signed in on another device. Continue here?';

      case AuthErrorCodes.sessionTakenOver:
        return 'You\'ve been signed out — this account is now active on another device.';

      case AuthErrorCodes.tokenExpired:
        return 'Your session expired. Please sign in again.';

      case AuthErrorCodes.invalidToken:
        return 'Your session is no longer valid. Please sign in again.';

      case AuthErrorCodes.refreshTokenReused:
        return 'Your session was reset for security. Please sign in again.';

      case AuthErrorCodes.refreshInFlight:
        // Transient — interceptor retries automatically. Surfaced only if
        // the retry also failed.
        return 'Reconnecting... please try again in a moment.';

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

      // ── Region (provider signup) ────────────────────────────────────
      case AuthErrorCodes.invalidRegion:
        return 'That region is no longer available. Go back and choose your region again, then re-enter the code.';

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
