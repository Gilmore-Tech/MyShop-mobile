import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/artisan_home/providers/active_job_provider.dart';
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import 'provider_status_provider.dart';
import 'socket_provider.dart';

/// Bridge that watches auth state and tears down session-scoped state on
/// logout (or any transition out of [AuthAuthenticated]).
///
/// Without this, a second user signing in on the same device inherits
/// the previous user's live socket connection, surfaced-jobs/rides set,
/// online flag, in-flight active ride or job, and previously-selected
/// role — all routed to the wrong identity until each provider happens
/// to refetch.
///
/// Must be watched once at app start so it stays subscribed for the
/// lifetime of the ProviderContainer.
final logoutCleanupBridgeProvider = Provider<void>((ref) {
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    final wasAuthed = prev is AuthAuthenticated;
    final isAuthed = next is AuthAuthenticated;
    if (!wasAuthed || isAuthed) return;

    debugPrint('[Logout] tearing down session-scoped state');

    // Tear down the socket so the old JWT isn't used for any further
    // emits. Invalidating disposes the SocketService via ref.onDispose
    // in socketServiceProvider.
    ref.invalidate(socketServiceProvider);

    // Forget which jobs/rides were already surfaced to the previous user so
    // the next user sees fresh open jobs/rides.
    ref.invalidate(surfacedJobIdsProvider);
    ref.invalidate(surfacedRideIdsProvider);

    // Drop any in-flight active ride / job. Without this a driver who
    // logs out mid-trip and an artisan who logs in next can briefly see
    // the stale ride in their home shell before the next /me/active
    // poll corrects it.
    ref.invalidate(activeRideProvider);
    ref.invalidate(activeJobProvider);

    // Reset online status — the next user starts offline on the home
    // screen regardless of what the previous user had set.
    ref.read(providerStatusProvider.notifier).goOffline();

    // Reset role to the default. The next sign-in's onAuthenticated
    // hook will overwrite this with the chosen role; resetting first
    // means a sign-in that bails before reaching onAuthenticated
    // (e.g. user backs out at OTP) doesn't leave the previous user's
    // role selection lying around.
    ref.read(providerTypeProvider.notifier).state = ProviderType.artisan;
  });
});
