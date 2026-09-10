import 'package:api_client/api_client.dart';

/// Automatic restore must retain intent for these failures. Explicit Go Online
/// continues to return its existing actionable messages.
class ProviderOnlineRestorePending implements Exception {
  const ProviderOnlineRestorePending();
}

bool isRetryableProviderRestoreError(ApiException error) {
  if (error.isNetworkError || error.isServerError) return true;
  if (error.errorCode == 'PROVIDER_REQUEST_BLOCK' ||
      error.errorCode == 'PROVIDER_REQUEST_WARNING') {
    return false;
  }
  if (error.statusCode == 408 || error.statusCode == 429) return true;
  const repairable = {
    'GPS_REQUIRED',
    'GPS_FIX_STALE',
    'GPS_FIX_OUT_OF_ORDER',
    'GPS_ACCURACY_REQUIRED',
    'GPS_LOCATION_STALE',
    'GPS_ACCURACY_INSUFFICIENT',
    'RATE_LIMIT_EXCEEDED',
    'OFFER_RECEIPT_CAPABILITY_REQUIRED',
  };
  if (repairable.contains(error.errorCode)) return true;
  final reasons = error.details?['reasonCodes'];
  return error.errorCode == 'PROVIDER_NOT_ELIGIBLE' &&
      reasons is List &&
      reasons.isNotEmpty &&
      reasons.every((reason) => repairable.contains(reason));
}
