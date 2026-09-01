import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/artisan_home/providers/active_job_provider.dart';
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import '../../features/profile/providers/verification_provider.dart';
import 'provider_status_provider.dart';
import 'socket_provider.dart';
import 'location_degradation_provider.dart';
import 'provider_location_session_provider.dart';
import 'provider_online_intent.dart';
import '../services/job_offer_receipt_service.dart';
import '../services/incoming_request_overlay_presenter.dart';
import '../services/local_notification_service.dart';

typedef JobRequestAlertCleanup = Future<void> Function({
  required String jobId,
  String? offerId,
});

/// Injectable boundary for native alert cleanup so account-switch behavior is
/// regression-testable without initializing platform notification plugins.
final jobRequestAlertCleanupProvider = Provider<JobRequestAlertCleanup>((ref) {
  return ({required String jobId, String? offerId}) =>
      clearIncomingRequestAlert(
        type: NotificationPayload.typeJobRequest,
        requestId: jobId,
        offerId: offerId,
        reason: 'logout',
      );
});

final incomingRequestRingtoneTeardownProvider =
    Provider<Future<void> Function()>((ref) {
  return () => LocalNotificationService.instance.stopIncomingRingtone();
});

/// Complete account boundary for every job-offer identity and presentation
/// state. Exposed as a provider-backed operation so regression tests can run
/// the same cleanup used by real logout/account replacement.
final jobOfferSessionCleanupProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    // Starts with a synchronous generation fence. Any exact receipt still in
    // flight for the outgoing account will now return null.
    final durablePurge = purgeStoredJobOffers();
    final exactOffers = Map<String, String>.from(
      ref.read(jobOfferIdByJobProvider),
    );
    final jobIds = <String>{
      ...exactOffers.keys,
      ...ref.read(pendingIncomingJobsProvider).map((job) => job.id),
    };
    final incomingJobId = ref.read(incomingJobRequestProvider)?.id;
    if (incomingJobId != null) jobIds.add(incomingJobId);
    final alertCleanup = ref.read(jobRequestAlertCleanupProvider);
    final alertTeardowns = <Future<void>>[
      for (final jobId in jobIds)
        alertCleanup(jobId: jobId, offerId: exactOffers[jobId]),
      // Account boundaries intentionally silence any legacy/unowned ringtone.
      ref.read(incomingRequestRingtoneTeardownProvider)(),
    ];
    ref.invalidate(surfacedJobIdsProvider);
    ref.read(incomingJobRequestProvider.notifier).state = null;
    ref.read(visibleJobRequestIdProvider.notifier).state = null;
    ref.read(visibleJobModalIdProvider.notifier).state = null;
    ref.read(jobOfferIdByJobProvider.notifier).state = <String, String>{};
    ref.read(lastJobOfferIdByJobProvider.notifier).state = <String, String>{};
    ref.read(jobOfferDeadlineByJobProvider.notifier).state =
        <String, DateTime>{};
    ref.read(jobOfferDismissalProvider.notifier).state = null;
    ref.read(pendingIncomingJobsProvider.notifier).clear();
    await Future.wait<void>([durablePurge, ...alertTeardowns]);
  };
});

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

    // AuthController owns exact-role Online-intent deletion; this bridge owns
    // only the in-memory identity and notice teardown.
    ref.read(availabilityRestoreNoticeProvider.notifier).state = null;
    ref.read(currentProviderOnlineIntentIdentityProvider.notifier).state = null;

    // Tear down the socket so the old JWT isn't used for any further
    // emits. Invalidating disposes the SocketService via ref.onDispose
    // in socketServiceProvider.
    ref.invalidate(socketServiceProvider);

    // Forget which jobs/rides were already surfaced to the previous user so
    // the next user sees fresh open jobs/rides.
    unawaited(ref.read(jobOfferSessionCleanupProvider)());
    ref.invalidate(surfacedRideIdsProvider);
    // Keep these controllers alive while the outgoing route completes its
    // deferred dispose callback; invalidating them here would leave that
    // callback holding disposed StateControllers.
    ref.read(incomingRideRequestProvider.notifier).state = null;
    ref.read(visibleRideRequestIdProvider.notifier).state = null;
    ref.read(visibleRideRequestOwnerProvider.notifier).state = null;
    ref.read(rideRequestNavigationInFlightProvider.notifier).state = <String>{};

    // Drop any in-flight active ride / job. Without this a driver who
    // logs out mid-trip and an artisan who logs in next can briefly see
    // the stale ride in their home shell before the next /me/active
    // poll corrects it.
    ref.invalidate(activeRideProvider);
    ref.invalidate(activeJobProvider);

    // Reset online status — the next user starts offline on the home
    // screen regardless of what the previous user had set.
    ref.read(providerStatusProvider.notifier).goOffline();
    ref.read(providerLocationSessionProvider.notifier).clear();
    ref.invalidate(providerLocationDegradationProvider);

    // Reset role to the default. The next sign-in's onAuthenticated
    // hook will overwrite this with the chosen role; resetting first
    // means a sign-in that bails before reaching onAuthenticated
    // (e.g. user backs out at OTP) doesn't leave the previous user's
    // role selection lying around.
    ref.read(providerTypeProvider.notifier).state = ProviderType.artisan;

    // Wipe BOTH role's local photo caches so the next account on this
    // device starts blank. Without this, registering Artisan after
    // logging out as Driver shows the Driver's selfie on the Artisan
    // home — the cached file path / Cloudinary URL outlive the auth
    // state. Invalidate the provider too so the next read rebuilds
    // with an empty state (and the new role's prefs keys).
    LocalProfilePhotoNotifier.clearAllRoles();
    ref.invalidate(localProfilePhotoProvider);
  });
});
