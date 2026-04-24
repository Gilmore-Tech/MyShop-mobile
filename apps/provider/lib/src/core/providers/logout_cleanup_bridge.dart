import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import 'provider_status_provider.dart';
import 'socket_provider.dart';

/// Bridge that watches auth state and tears down session-scoped state on
/// logout (or any transition out of [AuthAuthenticated]).
///
/// Without this, a second user signing in on the same device inherits:
///   - the previous user's live socket connection (events route to the
///     wrong identity until the socket naturally disconnects)
///   - the surfaced-jobs set (new user misses jobs that were marked as
///     already-seen for the previous user)
///   - the stale "online" flag in the status provider
///
/// Must be watched once at app start so it stays subscribed for the
/// lifetime of the ProviderContainer.
///
/// TODO(backend-B3): when DELETE /notifications/register-device ships,
/// add a call here so the backend also drops the FCM token binding. For
/// now, [FcmService.dispose] deletes the token on the device side only.
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

    // Forget which jobs were already surfaced to the previous user so
    // the next user sees fresh open jobs.
    ref.invalidate(surfacedJobIdsProvider);

    // Reset online status — the next user starts offline on the home
    // screen regardless of what the previous user had set.
    ref.read(providerStatusProvider.notifier).goOffline();
  });
});
