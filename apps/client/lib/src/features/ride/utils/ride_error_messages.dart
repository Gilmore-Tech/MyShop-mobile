import 'package:api_client/api_client.dart';

import '../../../core/utils/ride_service_area.dart';

class RideEstimateErrorCopy {
  const RideEstimateErrorCopy({
    required this.title,
    required this.message,
    this.showRetry = true,
  });

  final String title;
  final String message;
  final bool showRetry;
}

/// Stable client-owned copy for an exhausted ride match.
///
/// A completed search with no eligible driver is an availability outcome,
/// not a server failure. Never replace this with backend/provider prose.
const noDriversAvailableMessage =
    'All nearby drivers are busy or offline. Please try again.';

/// Classifies only stable machine fields from a realtime cancellation.
bool isNoDriversSocketCancellation({
  String? status,
  String? reason,
}) {
  final normalizedStatus = status?.trim().toLowerCase();
  final normalizedReason = reason?.trim().toLowerCase();
  return normalizedStatus == 'no_drivers' ||
      normalizedReason == 'no_drivers_available' ||
      normalizedReason == 'no_driver_available' ||
      normalizedReason == 'no_drivers' ||
      normalizedReason == 'no_driver';
}

/// Client-owned copy for realtime cancellation payloads.
///
/// The socket is authenticated, but its free-form `reason`/`message` fields
/// are still server prose and must not be rendered directly.
String rideSocketCancellationMessage({
  String? status,
  String? reason,
  String? cancelledBy,
}) {
  if (isNoDriversSocketCancellation(
    status: status,
    reason: reason,
  )) {
    return noDriversAvailableMessage;
  }
  if (reason?.trim().toLowerCase() == 'initialization_timeout') {
    return "We couldn't finish requesting your ride. Please try again.";
  }
  return switch (cancelledBy?.trim().toLowerCase()) {
    'client' => 'You cancelled this ride.',
    'driver' => 'The driver cancelled this ride.',
    'admin' => 'MyShop support cancelled this ride.',
    'system' => 'MyShop ended this ride because it could not continue.',
    _ => 'This ride was cancelled.',
  };
}

/// Client-owned copy for the advisory realtime delay event.
const rideSocketDriverDelayMessage =
    'Your driver is delayed, but the ride is still active.';

String rideRequestErrorMessage(ApiException error) {
  if (error.errorCode?.toUpperCase() == 'NO_DRIVERS_AVAILABLE') {
    return noDriversAvailableMessage;
  }

  return userSafeApiErrorMessage(
    error,
    fallback: "Couldn't request a ride. Please try again.",
    validationMessage:
        'Check the pickup, destination, and ride option, then try again.',
    conflictMessage:
        'Your ride request changed. Check for an active ride before retrying.',
  );
}

RideEstimateErrorCopy rideEstimateErrorCopy(Object error) {
  if (isOutsideRideServiceAreaError(error)) {
    return const RideEstimateErrorCopy(
      title: 'Outside service area',
      message: 'Ride booking currently operates in $rideServiceAreaName. '
          'Choose a pickup and destination inside the service area to see fares.',
      showRetry: false,
    );
  }

  if (error is NetworkException) {
    return RideEstimateErrorCopy(
      title: 'Could not load fare estimate',
      message: userSafeApiErrorMessage(
        error,
        fallback: 'Please try again in a moment.',
      ),
    );
  }

  if (error is ApiException) {
    return RideEstimateErrorCopy(
      title: 'Could not load fare estimate',
      message: userSafeApiErrorMessage(
        error,
        fallback: 'Please check the trip details and try again.',
        validationMessage: 'Check the pickup and destination, then try again.',
      ),
    );
  }

  return const RideEstimateErrorCopy(
    title: 'Could not load fare estimate',
    message: 'Please try again in a moment.',
  );
}

bool isOutsideRideServiceAreaError(Object error) {
  if (error is! ApiException) return false;
  return error.errorCode?.toUpperCase() == 'OUTSIDE_PILOT_REGION';
}
