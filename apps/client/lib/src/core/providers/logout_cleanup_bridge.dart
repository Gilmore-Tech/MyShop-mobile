import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/activity/providers/activity_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/home/providers/home_provider.dart';
import '../../features/ride/providers/ride_payment_provider.dart';
import '../../features/ride/providers/ride_provider.dart';
import '../../features/ride/providers/ride_search_provider.dart';
import '../di/providers.dart';
import 'nav_badge_provider.dart';
import 'socket_provider.dart';

/// Bridge that watches auth state and tears down session-scoped state on
/// logout (or any transition out of [AuthAuthenticated]).
///
/// Without this, a second user signing in on the same install inherits
/// the previous user's live socket, ride state, payment state, activity
/// feed, badge counts, recent places, and pending-payment records — all
/// keyed to the wrong identity.
///
/// AutoDispose providers are tolerated (they recreate cleanly), but
/// invalidating them too is harmless and keeps this list a single
/// source of truth for what "logout" tears down.
///
/// Must be watched once at app start so it stays subscribed for the
/// lifetime of the ProviderContainer.
final logoutCleanupBridgeProvider = Provider<void>((ref) {
  ref.listen<ClientAuthState>(clientAuthControllerProvider, (prev, next) {
    final wasAuthed = prev is AuthAuthenticated;
    final isAuthed = next is AuthAuthenticated;
    if (!wasAuthed || isAuthed) return;

    debugPrint('[Logout] tearing down session-scoped state');

    // Tear down the socket so the old JWT isn't reused for any further
    // emits. Disposes the SocketService via ref.onDispose in the
    // socketServiceProvider.
    ref.invalidate(socketServiceProvider);

    // Nav badges (unread chats, activity counts) are user-scoped.
    ref.invalidate(navBadgeProvider);

    // Activity feed (rides + jobs history). AutoDispose, but explicit
    // for safety: if any screen is still listening at logout, stale
    // entries flash until refetch.
    ref.invalidate(activityNotifierProvider);

    // Home surfaces (special offers + recent places) — recent places
    // is per-user; special offers usually aren't but cheap to refetch.
    ref.invalidate(specialOffersProvider);
    ref.invalidate(recentPlacesProvider);

    // Ride booking + tracking state. The ride-flow screens hold a deep
    // graph of in-memory state; reset everything that could carry the
    // previous user's identity into the next session.
    ref.invalidate(bookingPhaseProvider);
    ref.invalidate(bookingFailureMessageProvider);
    ref.invalidate(matchedDriverProvider);
    ref.invalidate(activeRideIdProvider);
    ref.invalidate(searchCountdownProvider);
    ref.invalidate(rideEtaProvider);
    ref.invalidate(tripEtaProvider);
    ref.invalidate(waitingCountdownProvider);
    ref.invalidate(rideTrackingPhaseProvider);
    ref.invalidate(rideMatchedViaSocketProvider);
    ref.invalidate(driversNotifiedProvider);
    ref.invalidate(rideReceiptProvider);
    ref.invalidate(tipStateProvider);
    ref.invalidate(selectedVehicleProvider);
    ref.invalidate(liveDriverPositionProvider);
    ref.invalidate(rideSearchProvider);
    ref.invalidate(ridePaymentNotifierProvider);

    // Pending payment records persisted to SharedPreferences. Must be
    // wiped on logout so a second user signing in on this install
    // can't see — or auto-resume — the previous user's in-flight
    // charges. SharedPreferences is shared per-process so storing
    // these without a per-user namespace means logout is the only
    // safe place to drop them.
    ref.read(pendingPaymentStoreProvider).clearAll().catchError((Object e) {
      debugPrint('[Logout] pendingPaymentStore.clearAll failed: $e');
    });
  });
});
