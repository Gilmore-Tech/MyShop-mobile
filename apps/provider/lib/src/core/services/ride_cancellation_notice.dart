import 'package:flutter/foundation.dart';

final Map<String, DateTime> _shownRiderCancellationNotices =
    <String, DateTime>{};
const Duration _noticeDedupeWindow = Duration(minutes: 2);

bool isRiderCancellationRevocation(Object? reason) =>
    reason?.toString().trim().toLowerCase() == 'cancelled_by_rider';

String? providerOfferCancellationMessage({
  Object? reason,
  Object? cancelledBy,
}) {
  final normalizedReason = reason?.toString().trim().toLowerCase();
  final normalizedActor = cancelledBy?.toString().trim().toLowerCase();
  if (normalizedReason == 'cancelled_by_rider' || normalizedActor == 'client') {
    return 'The rider cancelled this ride request.';
  }
  if (normalizedReason == 'cancelled_by_admin' || normalizedActor == 'admin') {
    return 'MyShop support cancelled this ride request.';
  }
  if (normalizedActor == 'system' ||
      normalizedReason == 'no_drivers_available' ||
      normalizedReason == 'cancelled_by_system') {
    return 'MyShop ended this ride request because it could not continue.';
  }
  return null;
}

/// Socket.IO and foreground FCM can deliver the same revocation milliseconds
/// apart. Only one path should show the in-app banner; the deterministic
/// system notification may still be refreshed safely.
bool claimRiderCancellationInAppNotice(String rideId) {
  return claimRideOfferResolutionInAppNotice(rideId);
}

bool claimRideOfferResolutionInAppNotice(String rideId) {
  final now = DateTime.now();
  _shownRiderCancellationNotices.removeWhere(
    (_, shownAt) => now.difference(shownAt) >= _noticeDedupeWindow,
  );
  if (_shownRiderCancellationNotices.containsKey(rideId)) return false;
  _shownRiderCancellationNotices[rideId] = now;
  return true;
}

@visibleForTesting
void resetRiderCancellationNoticeDedupe() {
  _shownRiderCancellationNotices.clear();
}
