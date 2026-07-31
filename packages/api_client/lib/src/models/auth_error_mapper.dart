import 'api_exception.dart';
import 'user_safe_api_error.dart';

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

  /// The private auth root or exact role account referenced by the refresh
  /// credential no longer exists/is active. These are explicit terminal
  /// backend decisions, not inferred from an HTTP status.
  static const userNotFound = 'USER_NOT_FOUND';
  static const roleAccountUnavailable = 'ROLE_ACCOUNT_UNAVAILABLE';
  static const roleAccountMismatch = 'ROLE_ACCOUNT_MISMATCH';

  /// The signed SID-bearing bootstrap proof no longer names the server's
  /// current recoverable legacy lineage.
  static const legacyBootstrapProofInvalid = 'LEGACY_BOOTSTRAP_PROOF_INVALID';

  /// Returned by /auth/verify-otp (400) during provider signup when the
  /// `regionId` carried by the earlier register call is unknown/inactive —
  /// practically only a stale-cache edge case. The app re-fetches
  /// `GET /v1/regions`, asks the user to re-select, and retries.
  static const invalidRegion = 'INVALID_REGION';

  /// Returned by registration when the requested exact role was soft-deleted
  /// and is still retained. Registration must not create a replacement role;
  /// the app offers the separate support/recovery path instead.
  static const roleAccountRetained = 'ROLE_ACCOUNT_RETAINED';
}

/// Maps [ApiException] instances to user-friendly, actionable error messages
/// for the auth flow (register, login, OTP verification).
///
/// Unknown backend prose is never returned to the UI.
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

  /// Adds only the server-generated UUID used to correlate support logs.
  static String messageWithSupportReference(Object error) {
    final safeMessage = message(error);
    final reference = supportReference(error);
    return reference == null
        ? safeMessage
        : '$safeMessage\nReference: $reference';
  }

  static String? supportReference(Object error) {
    if (error is! ApiException) return null;
    final raw = error.details?['supportReference'];
    if (raw is! String) return null;
    final reference = raw.trim().toLowerCase();
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(reference)
        ? reference
        : null;
  }

  /// Extracts per-field validation messages from a [ValidationException].
  /// Returns a map of field name → error message, or empty if unavailable.
  static Map<String, String> fieldErrors(Object error) {
    if (error is! ApiException || error.details == null) {
      return const {};
    }
    final result = <String, String>{};
    for (final entry in error.details!.entries) {
      final hasValidationValue = entry.value is String ||
          (entry.value is List && (entry.value as List).isNotEmpty);
      if (hasValidationValue) {
        result[entry.key] = _safeFieldValidationMessage(entry.key);
      }
    }
    return result;
  }

  /// True when the backend is telling us another device currently owns the
  /// active session and the user must choose whether to take it over.
  ///
  /// Production auth errors may arrive either as the canonical
  /// `ALREADY_LOGGED_IN_ELSEWHERE` code or as a 409 NestJS message envelope.
  /// Keep this tolerant so the UI always opens the takeover/support dialog.
  static bool isAlreadyLoggedInElsewhere(Object error) {
    if (error is! ApiException) return false;
    final code = error.errorCode?.toUpperCase();
    if (code == AuthErrorCodes.alreadyLoggedInElsewhere ||
        (code?.contains('ALREADY_LOGGED_IN') ?? false)) {
      return true;
    }
    final message = '${error.errorCode ?? ''} ${error.message}'.toLowerCase();
    return error.statusCode == 409 &&
        message.contains('already') &&
        message.contains('logged') &&
        (message.contains('device') ||
            message.contains('elsewhere') ||
            message.contains('session'));
  }

  /// Returns the short-lived exact-session recovery capability attached to a
  /// canonical blocked-device conflict. Never infer or persist this value.
  static String? sessionRecoveryChallenge(Object error) {
    if (error is! ApiException) return null;
    final value = error.details?['recoveryChallenge'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.length >= 32 && trimmed.length <= 128 ? trimmed : null;
  }

  /// Whether the backend explicitly guarantees that the OTP remains valid
  /// despite the request returning an error (for example, when it could not
  /// confirm that the SMS provider accepted the delivery).
  ///
  /// Do not infer this from a status code or message: cooldown and quota
  /// responses do not necessarily prove that a usable code exists.
  static bool hasActiveOtp(Object error) {
    return error is ApiException && error.details?['otpActive'] == true;
  }

  /// True only for the backend's stable retained-role registration fence.
  /// Never infer recovery eligibility from prose or a generic conflict.
  static bool requiresRoleRecoverySupport(Object error) {
    return error is ApiException &&
        error.errorCode == AuthErrorCodes.roleAccountRetained;
  }

  static String _networkMessage(NetworkException e) {
    return switch (e.kind) {
      NetworkFailureKind.offline =>
        'No internet connection. Check your network and try again.',
      NetworkFailureKind.timeout =>
        'Connection timed out. Check your internet and try again.',
      NetworkFailureKind.unavailable =>
        'Service temporarily unavailable. Please try again in a moment.',
    };
  }

  static String _apiMessage(ApiException e) {
    // Map known error codes to actionable messages.
    switch (e.errorCode) {
      // ── Registration ────────────────────────────────────────────────
      case 'PHONE_ALREADY_REGISTERED':
      case 'USER_ALREADY_EXISTS':
        return 'This phone number is already registered. Try signing in instead.';

      case 'DRIVER_ACCOUNT_EXISTS':
        return 'A driver account already exists for this phone number. Sign in instead.';

      case 'ARTISAN_ACCOUNT_EXISTS':
        return 'An artisan account already exists for this phone number. Sign in instead.';

      case 'ACCOUNT_EXISTS':
        return 'This provider account already exists. Sign in instead.';

      case 'EMAIL_ALREADY_EXISTS':
        return 'That email is already used by another account. Go back and enter a different email.';

      case AuthErrorCodes.roleAccountRetained:
        return 'This role was previously deleted and cannot be registered again. Contact support if you want to request recovery.';

      case 'ROLE_ACCOUNT_RECOVERY_DISABLED':
        return 'Account recovery is temporarily unavailable. Please contact support.';

      case 'ROLE_ACCOUNT_RECOVERY_WINDOW_CLOSED':
        return 'The 90-day recovery period for this role has ended. Please contact support.';

      case 'ROLE_ACCOUNT_RECOVERY_REQUEST_MISMATCH':
      case 'INVALID_OTP_FLOW':
        return 'This recovery verification no longer matches this phone, role, or device. Request a new code.';

      case 'ROLE_ACCOUNT_RECOVERY_RETRY':
        return 'The recovery state changed while you were submitting. Request a new code and try again.';

      case 'INVALID_PHONE':
      case 'INVALID_PHONE_FORMAT':
        return 'This phone number isn\'t valid. Enter a 9-digit Ghana number.';

      case 'REGISTRATION_DISABLED':
        return 'New sign-ups are temporarily paused. Please try again later.';

      case 'CATEGORIES_REQUIRED':
        return 'Select at least one service before continuing.';

      case 'INVALID_CATEGORY':
        return 'One of your selected services is no longer available. Go back and choose your services again.';

      case 'VEHICLE_DETAILS_REQUIRED':
        return 'Complete all vehicle details before continuing.';

      case 'INVALID_VEHICLE_PLATE':
        return 'Enter a valid Ghana vehicle plate and try again.';

      case 'VEHICLE_PLATE_IN_USE':
        return 'That vehicle plate is already registered. Check it or contact support.';

      case 'VEHICLE_CREATION_FAILED':
        return 'We could not finish creating the vehicle. Please contact support with the reference below.';

      case 'RIDE_CATEGORIES_REQUIRED':
        return 'Select at least one ride category before continuing.';

      case 'INVALID_RIDE_CATEGORY':
        return 'One of your selected ride categories is no longer available. Go back and choose again.';

      case 'INVALID_REFERRAL_CODE':
        return 'That referral code is not valid. Correct it or remove it to continue.';

      case 'SELF_REFERRAL_NOT_ALLOWED':
        return 'You cannot use a referral code owned by one of your own accounts. Remove it to continue.';

      case 'ROLE_ACCOUNT_REFERRALS_SUSPENDED':
        return 'Referrals are temporarily unavailable. Remove the optional referral code to continue.';

      case 'REFERRAL_ALREADY_LINKED':
        return 'A referral is already linked to this provider account. Remove the code or contact support.';

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
        return 'This code has expired. Go back and request a new code.';

      case 'OTP_MAX_ATTEMPTS':
      case 'TOO_MANY_OTP_ATTEMPTS':
        return 'Too many incorrect attempts. Wait a moment, then go back and request a new code.';

      case 'OTP_SEND_FAILED':
        return 'We couldn\'t send the code. Check your phone number and try again.';

      case 'OTP_DELIVERY_FAILED':
        if (hasActiveOtp(e)) {
          return 'We couldn\'t confirm SMS delivery. Your code is still active. Wait for it or use resend.';
        }
        return 'We couldn\'t deliver the code. Please try again.';

      case 'OTP_DELIVERY_RATE_LIMITED':
        if (hasActiveOtp(e)) {
          return 'SMS delivery is busy right now. Your code is still active. Wait a moment or use resend.';
        }
        return 'Too many code delivery attempts. Please wait before trying again.';

      case 'OTP_COOLDOWN':
        return 'Please wait before requesting another code.';

      case 'OTP_DAILY_LIMIT':
        return 'You\'ve requested too many new codes today. Please try again later or contact support.';

      case 'OTP_RESEND_COOLDOWN':
        return 'Please wait before resending this code.';

      case 'OTP_RESEND_LIMIT':
        return 'You\'ve reached the resend limit for this code. Enter the current code or go back and request a new one later.';

      case 'OTP_NOT_FOUND':
        return 'This code has expired or is no longer active. Go back and request a new code.';

      case 'INVALID_OTP_STATE':
        return 'This code can no longer be used. Go back and request a new code.';

      case 'CHANNEL_DISABLED':
      case 'CHANNEL_UNAVAILABLE':
        return 'That delivery option is unavailable. Please try another channel.';

      case 'OTP_ISSUANCE_CONTROL_UNAVAILABLE':
      case 'OTP_STATE_CONTROL_UNAVAILABLE':
        return 'Code requests are temporarily unavailable. Please try again shortly.';

      case 'OTP_RESEND_CONTROL_UNAVAILABLE':
        return 'Code resend is temporarily unavailable. Please try again shortly.';

      case 'OTP_VERIFICATION_CONTROL_UNAVAILABLE':
        return 'Code verification is temporarily unavailable. Please try again shortly.';

      case 'OTP_RATE_LIMITED':
      case 'RATE_LIMITED':
      case 'TOO_MANY_REQUESTS':
        return 'Too many requests. Please wait a moment before trying again.';

      // ── Region (provider signup) ────────────────────────────────────
      case AuthErrorCodes.invalidRegion:
        return 'That region is no longer available. Go back and choose your region again, then re-enter the code.';

      case 'LEGAL_DOCUMENT_CHANGED':
        return 'The Terms or Privacy Notice changed. Go back, review and accept the current versions.';

      case 'LEGAL_DOCUMENTS_UNAVAILABLE':
      case 'DOCUMENT_NOT_FOUND':
        return 'The current Terms and Privacy Notice are temporarily unavailable. Please try again shortly.';

      case 'INVALID_REGISTRATION_ROLE':
        return 'Return to account type selection and choose Driver or Artisan again.';

      // ── Validation (422) ────────────────────────────────────────────
      case 'VALIDATION_ERROR':
      case 'VALIDATION_FAILED':
        return _validationSummary(e);

      // ── Server ──────────────────────────────────────────────────────
      case 'INTERNAL_ERROR':
      case 'SERVER_ERROR':
        return 'Service temporarily unavailable. Please try again in a moment.';

      default:
        return userSafeApiErrorMessage(
          e,
          fallback: 'Something went wrong. Please try again.',
          conflictMessage:
              'That account state changed. Return to sign in and try again.',
          validationMessage: 'Check the information you entered and try again.',
        );
    }
  }

  /// Builds a user-readable summary from validation error details.
  static String _validationSummary(ApiException e) {
    final fields = fieldErrors(e);
    if (fields.isEmpty) {
      return 'Check the information you entered and try again.';
    }
    // Show the first field error as the main message.
    return fields.values.first;
  }

  static String _safeFieldValidationMessage(String field) {
    return switch (field.toLowerCase()) {
      'phone' || 'phonenumber' => 'Enter a valid 9-digit Ghana phone number.',
      'otp' || 'code' => 'Enter the verification code sent to you.',
      'firstname' ||
      'lastname' ||
      'name' =>
        'Enter a valid name using letters and common punctuation.',
      'email' => 'Enter a valid email address.',
      'regionid' || 'region' => 'Choose an available region.',
      'role' => 'Choose the account type you want to use.',
      _ => 'Check this field and try again.',
    };
  }
}
