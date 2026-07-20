import 'api_exception.dart';

/// Converts an API failure into stable, user-facing copy without ever
/// returning backend prose. The server message remains available on
/// [ApiException] for structured logs, but it may contain internal details,
/// provider wording, identifiers, or text that is not appropriate for users.
///
/// Feature-specific code should map its known machine codes first, then use
/// this function for the unknown/default branch.
String userSafeApiErrorMessage(
  ApiException error, {
  required String fallback,
  String? unauthorizedMessage,
  String? forbiddenMessage,
  String? notFoundMessage,
  String? conflictMessage,
  String? validationMessage,
}) {
  if (error is NetworkException) {
    return 'No internet connection. Check your network and try again.';
  }
  if (error.isServerError) {
    return 'Our servers are having trouble. Please try again in a moment.';
  }

  if (error.errorCode == 'RATE_LIMITED' ||
      error.errorCode == 'TOO_MANY_REQUESTS' ||
      error.statusCode == 429) {
    return 'Too many attempts. Wait a moment, then try again.';
  }

  return switch (error.statusCode) {
    401 =>
      unauthorizedMessage ?? 'Your session expired. Sign in again, then retry.',
    403 =>
      forbiddenMessage ?? "This account isn't allowed to perform that action.",
    404 => notFoundMessage ??
        'That item is no longer available. Refresh and try again.',
    409 => conflictMessage ??
        'This changed before the action completed. Refresh and try again.',
    422 =>
      validationMessage ?? 'Check the information you entered and try again.',
    _ => fallback,
  };
}
