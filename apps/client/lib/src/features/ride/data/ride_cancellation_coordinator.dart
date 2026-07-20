import 'package:api_client/api_client.dart';

/// Result of a client cancellation attempt after reconciling ambiguous writes
/// against the authoritative ride row.
class RideCancellationResult {
  const RideCancellationResult._({
    required this.confirmedCancelled,
    required this.reconciled,
    required this.message,
    this.response = const <String, dynamic>{},
  });

  factory RideCancellationResult.cancelled(
    Map<String, dynamic> response, {
    bool reconciled = false,
  }) {
    return RideCancellationResult._(
      confirmedCancelled: true,
      reconciled: reconciled,
      message: 'Ride cancelled.',
      response: response,
    );
  }

  factory RideCancellationResult.notCancelled(String message) {
    return RideCancellationResult._(
      confirmedCancelled: false,
      reconciled: true,
      message: message,
    );
  }

  factory RideCancellationResult.unknown() {
    return const RideCancellationResult._(
      confirmedCancelled: false,
      reconciled: false,
      message:
          "We couldn't confirm whether the ride was cancelled. Keep this ride open while we check again.",
    );
  }

  final bool confirmedCancelled;
  final bool reconciled;
  final String message;
  final Map<String, dynamic> response;
}

/// Cancels once, then reads the ride back whenever the write result is
/// ambiguous or rejected. Local ride state may be cleared only when this
/// returns [RideCancellationResult.confirmedCancelled] as true.
///
/// This covers the important timeout-after-commit case: retrying blindly could
/// show a false failure because the already-cancelled ride is no longer
/// cancellable, while clearing blindly could strand an active backend ride.
Future<RideCancellationResult> cancelRideWithAuthority({
  required RideService rideService,
  required String rideId,
  required String reason,
}) async {
  Object? cancellationError;
  try {
    final response = await rideService.cancelRide(rideId, reason: reason);
    return RideCancellationResult.cancelled(response);
  } catch (error) {
    cancellationError = error;
  }

  try {
    final snapshot = await rideService.getRide(rideId);
    final status = snapshot['status']?.toString().trim().toLowerCase();
    if (status == 'cancelled' || status == 'canceled') {
      return RideCancellationResult.cancelled(
        const <String, dynamic>{},
        reconciled: true,
      );
    }

    return RideCancellationResult.notCancelled(
      _cancellationFailureMessage(cancellationError, status),
    );
  } catch (_) {
    return RideCancellationResult.unknown();
  }
}

String _cancellationFailureMessage(Object? error, String? authoritativeStatus) {
  if (authoritativeStatus == 'in_progress') {
    return 'This trip has already started and can no longer be cancelled.';
  }
  if (authoritativeStatus == 'completed') {
    return 'This ride has already ended and can no longer be cancelled.';
  }

  final code = error is ApiException ? error.errorCode : null;
  return switch (code) {
    'RIDE_NOT_FOUND' =>
      'This ride could not be found. Refresh your trips and try again.',
    'NOT_YOUR_RIDE' ||
    'PROFILE_REQUIRED' =>
      'This account is not allowed to cancel the ride.',
    'RIDE_NOT_CANCELLABLE' => 'This ride can no longer be cancelled.',
    'RATE_LIMITED' ||
    'TOO_MANY_REQUESTS' =>
      'Too many attempts. Wait a moment, then try again.',
    _ => 'Could not cancel the ride. Please try again.',
  };
}
