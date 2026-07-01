/// Post-trip contact window.
///
/// For 24h after a ride/job *completes*, the backend exposes the
/// counterparty's real number on the booking snapshot so the two sides can
/// reconnect (e.g. a forgotten item). History screens display that number as
/// read-only text — never a call affordance — and hide it once the window
/// closes. The backend nulls the field server-side; this mirror guards the
/// UI client-side so a stale/cached snapshot can't keep the number visible
/// past the window.
const Duration postTripContactWindow = Duration(hours: 24);

/// Whether [completedAt] is non-null and within [postTripContactWindow] of
/// now. Returns false for null, future, or expired timestamps.
bool isWithinPostTripContactWindow(DateTime? completedAt) {
  if (completedAt == null) return false;
  final elapsed = DateTime.now().difference(completedAt);
  return !elapsed.isNegative && elapsed < postTripContactWindow;
}
