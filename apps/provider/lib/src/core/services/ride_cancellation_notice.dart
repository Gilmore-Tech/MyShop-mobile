import 'package:flutter/foundation.dart';

final Map<String, DateTime> _shownRiderCancellationNotices =
    <String, DateTime>{};
const Duration _noticeDedupeWindow = Duration(minutes: 2);

bool isRiderCancellationRevocation(Object? reason) =>
    reason?.toString().trim().toLowerCase() == 'cancelled_by_rider';

/// Socket.IO and foreground FCM can deliver the same revocation milliseconds
/// apart. Only one path should show the in-app banner; the deterministic
/// system notification may still be refreshed safely.
bool claimRiderCancellationInAppNotice(String rideId) {
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
