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

RideEstimateErrorCopy rideEstimateErrorCopy(Object error) {
  if (_isOutsidePilotRegion(error)) {
    return const RideEstimateErrorCopy(
      title: 'Outside service area',
      message: 'Ride booking currently operates in $rideServiceAreaName. '
          'Choose a pickup and destination inside the service area to see fares.',
      showRetry: false,
    );
  }

  if (error is NetworkException) {
    return const RideEstimateErrorCopy(
      title: 'Could not load fare estimate',
      message: 'Check your connection and try again.',
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

bool _isOutsidePilotRegion(Object error) {
  if (error is! ApiException) return false;
  final code = error.errorCode?.toUpperCase();
  if (code == 'OUTSIDE_PILOT_REGION') return true;
  final message = '${error.errorCode ?? ''} ${error.message}'.toLowerCase();
  return error.statusCode == 400 &&
      message.contains('outside') &&
      (message.contains('pilot') || message.contains('service area'));
}
