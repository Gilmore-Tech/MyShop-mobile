import 'package:api_client/api_client.dart';

/// Whether a failed destination commit must discard its single-use preview.
bool destinationPreviewNoLongerUsable(String? code) => const {
      'RIDE_DESTINATION_PREVIEW_EXPIRED',
      'RIDE_DESTINATION_PREVIEW_INVALID',
      'RIDE_DESTINATION_PREVIEW_REVISION_MISMATCH',
      'RIDE_DESTINATION_PREVIEW_STALE',
      'RIDE_DESTINATION_PREVIEW_USED',
      'RIDE_DESTINATION_LIMIT_CHANGED',
      'RIDE_ROUTE_REVISION_CHANGED',
      'RIDE_ROUTE_CHANGED',
      'RIDE_QUOTE_CHANGED',
      // The ride has crossed a terminal boundary, so retrying the same
      // confirmation token cannot succeed.
      'RIDE_DESTINATION_NOT_EDITABLE',
      'RIDE_DESTINATION_CHANGE_NOT_ALLOWED',
      'RIDE_COMPLETION_ALREADY_STARTED',
      'RIDE_PAYMENT_ALREADY_EXISTS',
      'RIDE_HAS_QUEUED_SUCCESSOR',
      'INVALID_STATUS_TRANSITION',
      'RIDE_NOT_ACTIVE',
      // Compatibility aliases used by earlier API builds.
      'DESTINATION_CHANGE_PREVIEW_EXPIRED',
      'DESTINATION_CHANGE_TOKEN_EXPIRED',
      'PREVIEW_TOKEN_EXPIRED',
      'ROUTE_REVISION_MISMATCH',
      'STALE_ROUTE_REVISION',
    }.contains(code);

/// Stable, actionable rider copy for the destination-change API contract.
///
/// Raw backend errors are deliberately not shown; only reviewed machine codes
/// reach the UI.
String friendlyRideDestinationChangeError(ApiException error) {
  switch (error.errorCode) {
    case 'RIDE_DESTINATION_EDIT_DISABLED':
      return 'Changing the drop-off is temporarily turned off. Continue to the '
          'current destination or contact support.';
    case 'RIDE_DESTINATION_EDIT_CONFIG_UNAVAILABLE':
      return 'Drop-off changes are unavailable right now because pricing '
          'controls could not be verified. Please try again later.';
    case 'RIDE_DESTINATION_PREVIEW_EXPIRED':
    case 'DESTINATION_CHANGE_PREVIEW_EXPIRED':
    case 'DESTINATION_CHANGE_TOKEN_EXPIRED':
    case 'PREVIEW_TOKEN_EXPIRED':
      return 'The fare preview expired. Review the fare again.';
    case 'RIDE_DESTINATION_PREVIEW_USED':
      return 'That fare preview was already used. Review the latest fare again.';
    case 'RIDE_DESTINATION_PREVIEW_STALE':
      return 'The driver moved after this preview. Review the latest fare again.';
    case 'RIDE_DESTINATION_PREVIEW_INVALID':
    case 'RIDE_DESTINATION_PREVIEW_REVISION_MISMATCH':
      return 'That fare preview is no longer valid. Review the fare again.';
    case 'RIDE_ROUTE_REVISION_CHANGED':
    case 'RIDE_ROUTE_CHANGED':
    case 'RIDE_QUOTE_CHANGED':
    case 'RIDE_DESTINATION_LIMIT_CHANGED':
    case 'ROUTE_REVISION_MISMATCH':
    case 'STALE_ROUTE_REVISION':
      return 'The route changed while you were editing it. Refresh and review '
          'the latest fare again.';
    case 'OUTSIDE_PILOT_REGION':
    case 'DESTINATION_OUT_OF_PILOT_REGION':
    case 'STOP_OUT_OF_PILOT_REGION':
      return 'That destination is outside the active service area.';
    case 'RIDE_DESTINATION_CHANGE_TOO_LARGE':
      return 'That drop-off is too far from the current route. Choose a closer '
          'destination or arrange a new ride.';
    case 'RIDE_DESTINATION_REPRICE_LOCATION_STALE':
      return 'Waiting for a fresh driver location. Please try the drop-off '
          'change again in a moment.';
    case 'RIDE_DESTINATION_REPRICE_TRAIL_UNTRUSTED':
      return 'The trip needs a little more verified driving history before the '
          'fare can be recalculated. Please try again shortly.';
    case 'RIDE_DESTINATION_ADDRESS_REQUIRED':
      return 'Choose a named destination before reviewing the fare.';
    case 'RIDE_DESTINATION_UNCHANGED':
      return 'That is already the current drop-off.';
    case 'RIDE_DESTINATION_NOT_EDITABLE':
    case 'RIDE_DESTINATION_CHANGE_NOT_ALLOWED':
    case 'RIDE_COMPLETION_ALREADY_STARTED':
    case 'INVALID_STATUS_TRANSITION':
    case 'RIDE_NOT_ACTIVE':
      return "The drop-off can only be changed after the trip starts and before it completes.";
    case 'RIDE_PAYMENT_ALREADY_EXISTS':
    case 'RIDE_HAS_QUEUED_SUCCESSOR':
      return 'This ride is already being completed or paid. The drop-off can no '
          'longer be changed.';
    case 'RIDE_DESTINATION_LOYALTY_REFUND_REQUIRED':
      return 'Support must adjust the redeemed points before this lower fare can '
          'be applied.';
    case 'RIDE_TOLL_SNAPSHOT_INVALID':
    case 'RIDE_MULTIPLE_TOLLS_UNSUPPORTED':
    case 'RIDE_TOLL_REPRICE_UNAVAILABLE':
      return 'The new route toll could not be verified safely. Keep the current '
          'drop-off or contact support.';
    case 'RIDE_ROUTE_REPRICE_INVALID':
      return 'The new fare could not be verified safely. Please try again later.';
    default:
      return userSafeApiErrorMessage(
        error,
        fallback: "Couldn't change the drop-off. Please try again.",
        conflictMessage:
            'The route changed before confirmation. Review the fare again.',
      );
  }
}
