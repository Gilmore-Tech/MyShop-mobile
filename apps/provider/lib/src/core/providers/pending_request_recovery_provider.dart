import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../app/router.dart' show goRouterProvider;
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../di/providers.dart';
import '../services/incoming_request_overlay_presenter.dart';
import '../services/job_offer_receipt_service.dart';
import '../services/local_notification_service.dart';
import '../services/ride_cancellation_notice.dart';
import '../services/ride_offer_receipt_service.dart';
import 'app_lifecycle_provider.dart';
import 'nav_badge_provider.dart';
import 'service_notice_provider.dart';
import 'socket_provider.dart';

final _pendingRequestRecoveryScheduler = PendingRequestRecoveryScheduler();

/// Reconciles provider-targeted ride/job requests that arrived while the app
/// was backgrounded, terminated, or opened manually instead of via a push tap.
///
/// Socket events are still the low-latency path. This is the safety net that
/// prevents a push tap from landing on a blank/home screen when the in-memory
/// request payload was lost during process sleep.
final pendingRequestRecoveryBridgeProvider = Provider<void>((ref) {
  final auth = ref.watch(authControllerProvider);
  final foregrounded = ref.watch(appForegroundedProvider);
  ref.watch(serviceNoticeProvider.select((state) => state.recoveryEpoch));
  if (auth is! AuthAuthenticated || !foregrounded) return;
  _schedulePendingRequestRecovery(ref);
});

void _schedulePendingRequestRecovery(Ref ref) {
  _pendingRequestRecoveryScheduler.schedule(
    () => _recoverPendingRequests(ref),
  );
}

Future<void> recoverPendingRequestsNow(Ref ref) => _recoverPendingRequests(ref);

/// Coalesces recovery triggers while preserving one request that arrives
/// during the five-second cooldown. The retained trigger runs after only the
/// remaining delay, so a readiness recovery cannot be lost merely because an
/// earlier offline attempt started moments before connectivity returned.
@visibleForTesting
class PendingRequestRecoveryScheduler {
  PendingRequestRecoveryScheduler({
    this.minimumInterval = const Duration(seconds: 5),
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  })  : _now = now ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  final Duration minimumInterval;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _delay;

  DateTime? _lastStartedAt;
  Future<void>? _inFlight;
  Future<void>? _delayedPump;
  Future<void> Function()? _latestRecovery;
  bool _pending = false;

  void schedule(Future<void> Function() recovery) {
    _latestRecovery = recovery;
    _pending = true;
    _pump();
  }

  void _pump() {
    if (!_pending || _inFlight != null || _delayedPump != null) return;

    final now = _now();
    final last = _lastStartedAt;
    if (last != null) {
      final elapsed = now.isAfter(last) ? now.difference(last) : Duration.zero;
      if (elapsed < minimumInterval) {
        final wait = _delay(minimumInterval - elapsed);
        _delayedPump = wait;
        unawaited(
          wait.whenComplete(() {
            if (!identical(_delayedPump, wait)) return;
            _delayedPump = null;
            _pump();
          }),
        );
        return;
      }
    }

    final recovery = _latestRecovery;
    if (recovery == null) return;
    _pending = false;
    _lastStartedAt = now;
    final attempt = _runRecovery(recovery);
    _inFlight = attempt;
    unawaited(
      attempt.whenComplete(() {
        if (!identical(_inFlight, attempt)) return;
        _inFlight = null;
        _pump();
      }),
    );
  }

  Future<void> _runRecovery(Future<void> Function() recovery) async {
    try {
      await recovery();
    } catch (error) {
      debugPrint('[PendingRequestRecovery] scheduled attempt failed: $error');
    }
  }
}

/// Fetch the first still-actionable pending ride request without relying on
/// the shell-level IncomingRequestListener. Used by the /ride-request fallback
/// route during notification/cold-start timing gaps: that route sits outside
/// the shell, so setting [incomingRideRequestProvider] alone would not surface
/// the real request.
typedef PendingRideRequestRecovery = Future<Ride?> Function(String? rideId);

/// Captures every dependency needed by widget-owned request recovery before an
/// asynchronous gap. A notification route may be replaced while its REST calls
/// are still running; retaining [WidgetRef] inside completion callbacks would
/// then attempt an inherited-widget lookup through a deactivated element.
PendingRideRequestRecovery capturePendingRideRequestRecovery(WidgetRef ref) {
  final requestService = ref.read(providerRequestServiceProvider);
  final rideService = ref.read(rideServiceProvider);
  final deadlineController = ref.read(rideRequestDeadlineByIdProvider.notifier);
  final offerController = ref.read(rideOfferIdByRideProvider.notifier);

  return (String? rideId) => _recoverPendingRideRequest(
        rideId: rideId,
        listPendingRequests: () => requestService.listPendingRequests(),
        fetchRide: rideService.getRide,
        storeDeadline: (rideId, deadline) {
          deadlineController.update(
            (m) => {...m, rideId: deadline},
          );
        },
        storeOfferId: (rideId, offerId) {
          offerController.update(
            (offers) => {...offers, rideId: offerId},
          );
        },
      );
}

Future<Ride?> recoverPendingRideRequest(WidgetRef ref) {
  return capturePendingRideRequestRecovery(ref)(null);
}

Future<Ride?> recoverPendingRideRequestById(WidgetRef ref, String rideId) {
  return capturePendingRideRequestRecovery(ref)(rideId);
}

/// Same direct ride-request recovery as [recoverPendingRideRequest], but
/// callable from service providers such as the FCM tap bridge where a
/// [WidgetRef] is not available.
Future<Ride?> recoverPendingRideRequestFromRef(Ref ref) {
  return _recoverPendingRideRequest(
    listPendingRequests: () =>
        ref.read(providerRequestServiceProvider).listPendingRequests(),
    fetchRide: ref.read(rideServiceProvider).getRide,
    storeDeadline: (rideId, deadline) {
      ref.read(rideRequestDeadlineByIdProvider.notifier).update(
            (m) => {...m, rideId: deadline},
          );
    },
    storeOfferId: (rideId, offerId) {
      ref.read(rideOfferIdByRideProvider.notifier).update(
            (offers) => {...offers, rideId: offerId},
          );
    },
  );
}

Future<Ride?> recoverPendingRideRequestByIdFromRef(Ref ref, String rideId) {
  return _recoverPendingRideRequest(
    rideId: rideId,
    listPendingRequests: () =>
        ref.read(providerRequestServiceProvider).listPendingRequests(),
    fetchRide: ref.read(rideServiceProvider).getRide,
    storeDeadline: (rideId, deadline) {
      ref.read(rideRequestDeadlineByIdProvider.notifier).update(
            (m) => {...m, rideId: deadline},
          );
    },
    storeOfferId: (rideId, offerId) {
      ref.read(rideOfferIdByRideProvider.notifier).update(
            (offers) => {...offers, rideId: offerId},
          );
    },
  );
}

Future<Ride?> _recoverPendingRideRequest({
  String? rideId,
  required Future<List<ProviderPendingRequest>> Function() listPendingRequests,
  required Future<Map<String, dynamic>> Function(String rideId) fetchRide,
  required void Function(String rideId, DateTime deadline) storeDeadline,
  required void Function(String rideId, String offerId) storeOfferId,
}) async {
  try {
    final requests = await listPendingRequests().timeout(
      const Duration(seconds: 10),
    );
    for (final request in requests) {
      if (request.kind != ProviderRequestKind.ride) continue;
      if (rideId != null && request.id != rideId) continue;
      final ride = await _readPendingRide(
        request,
        fetchRide,
      );
      if (ride != null && request.expiresAt != null) {
        storeDeadline(ride.id, request.expiresAt!);
      }
      if (ride != null && request.offerId != null) {
        storeOfferId(ride.id, request.offerId!);
      }
      return ride;
    }
  } catch (e) {
    debugPrint('[PendingRequestRecovery] ride lookup failed: $e');
  }
  return null;
}

Future<void> _recoverPendingRequests(Ref ref) async {
  try {
    final expectedSession = ref.read(currentAuthSessionIdentityProvider);
    if (expectedSession == null) return;
    final recovery = await fetchProviderRequestRecovery(
      readStoredOffers: readStoredRideOfferIdentities,
      readStoredJobOffers: readStoredJobOfferIdentities,
      recover: (knownOfferIds) => ref
          .read(providerRequestServiceProvider)
          .recoverPendingRequests(knownOfferIds: knownOfferIds)
          .timeout(const Duration(seconds: 10)),
    );
    if (recovery == null) return;
    if (ref.read(currentAuthSessionIdentityProvider) != expectedSession) return;
    final resolvedRideIds =
        await _applyRideOfferResolutions(ref, recovery.resolutions);
    final requests = recovery.requests;
    final freshJobOfferIds = <String, String>{
      for (final request in requests)
        if (request.kind == ProviderRequestKind.job &&
            request.offerId != null &&
            request.offerId!.isNotEmpty)
          request.id: request.offerId!,
    };
    await _applyJobOfferResolutions(
      ref,
      recovery.resolutions,
      freshJobOfferIds: freshJobOfferIds,
    );
    if (requests.isEmpty) {
      final visibleRideId = ref.read(visibleRideRequestIdProvider);
      if (shouldApplyGenericPendingRideDismissal(
        visibleRideId: visibleRideId,
        resolvedRideIds: resolvedRideIds,
      )) {
        ref.read(rideOfferDismissalProvider.notifier).state =
            RideOfferDismissal(
          rideId: visibleRideId!,
          reason: 'no_longer_pending',
        );
      }
      return;
    }

    final router = ref.read(goRouterProvider);
    final currentPath = router.routerDelegate.currentConfiguration.uri.path;
    final onRideRequest = currentPath == '/ride-request';
    final onJobRequest = currentPath == '/job-request';

    for (final request in requests) {
      switch (request.kind) {
        case ProviderRequestKind.ride:
          if (onRideRequest) continue;
          await _surfaceRideRequest(ref, request);
          return;
        case ProviderRequestKind.job:
          if (onJobRequest) {
            final currentOfferId =
                ref.read(jobOfferIdByJobProvider)[request.id];
            final recoveredOfferId = request.offerId;
            // Keep the already-open exact offer. A different exact identity
            // for the same job is a new directed opportunity and must be
            // allowed through so it can replace the terminal older screen.
            if (recoveredOfferId == null ||
                recoveredOfferId.isEmpty ||
                recoveredOfferId == currentOfferId) {
              continue;
            }
          }
          await _surfaceJobRequest(
            ref,
            request,
            expectedSession: expectedSession,
          );
          return;
      }
    }
  } catch (e) {
    debugPrint('[PendingRequestRecovery] failed: $e');
  }
}

Future<void> _applyJobOfferResolutions(
  Ref ref,
  List<ProviderRequestResolution> resolutions, {
  required Map<String, String> freshJobOfferIds,
}) async {
  for (final resolution in resolutions) {
    if (resolution.kind != ProviderRequestKind.job) continue;
    final jobId = resolution.jobId;
    if (jobId.isEmpty) continue;
    final currentOfferId = ref.read(jobOfferIdByJobProvider)[jobId];
    final hasFreshReplacement = terminalJobOfferHasFreshReplacement(
      terminalOfferId: resolution.offerId,
      freshOfferId: freshJobOfferIds[jobId],
    );
    if (jobOfferTerminalMatchesCurrent(
      currentOfferId: currentOfferId,
      terminalOfferId: resolution.offerId,
    )) {
      if (!hasFreshReplacement) {
        ref.read(jobOfferDismissalProvider.notifier).state = JobOfferDismissal(
          jobId: jobId,
          reason: resolution.resolutionReason ?? 'resolved',
          offerId: resolution.offerId,
        );
        ref.read(pendingIncomingJobsProvider.notifier).remove(jobId);
        if (ref.read(incomingJobRequestProvider)?.id == jobId) {
          ref.read(incomingJobRequestProvider.notifier).state = null;
        }
      }
      ref
          .read(jobOfferIdByJobProvider.notifier)
          .update((offers) => {...offers}..remove(jobId));
      ref
          .read(jobOfferDeadlineByJobProvider.notifier)
          .update((deadlines) => {...deadlines}..remove(jobId));
    }
    await clearIncomingRequestAlert(
      type: NotificationPayload.typeJobRequest,
      requestId: jobId,
      offerId: resolution.offerId,
      reason: resolution.resolutionReason ?? 'resolved',
    );
    await clearStoredJobOffer(resolution.offerId);
  }
}

@visibleForTesting
bool terminalJobOfferHasFreshReplacement({
  required String terminalOfferId,
  required String? freshOfferId,
}) {
  final fresh = freshOfferId?.trim();
  return fresh != null && fresh.isNotEmpty && fresh != terminalOfferId.trim();
}

/// Reads durable identities and asks the server for their exact state without
/// consuming any local identity on a transient fetch failure.
@visibleForTesting
Future<ProviderRequestRecoveryResult?> fetchProviderRequestRecovery({
  required Future<List<StoredRideOfferIdentity>> Function() readStoredOffers,
  Future<List<StoredJobOfferIdentity>> Function()? readStoredJobOffers,
  required Future<ProviderRequestRecoveryResult> Function(
    List<String> knownOfferIds,
  ) recover,
}) async {
  try {
    final storedOffers = await readStoredOffers();
    final storedJobOffers =
        await readStoredJobOffers?.call() ?? const <StoredJobOfferIdentity>[];
    final exactOffers = <({String offerId, DateTime handoffAt})>[
      for (final identity in storedOffers)
        (
          offerId: identity.offerId,
          handoffAt: identity.localHandoffAt,
        ),
      for (final identity in storedJobOffers)
        (
          offerId: identity.offerId,
          handoffAt: identity.localHandoffAt,
        ),
    ]..sort((left, right) => right.handoffAt.compareTo(left.handoffAt));
    return await recover(
      exactOffers
          .map((identity) => identity.offerId)
          .toSet()
          .take(maxKnownProviderOfferIds)
          .toList(growable: false),
    );
  } catch (error) {
    debugPrint('[PendingRequestRecovery] request fetch failed: $error');
    return null;
  }
}

Future<Set<String>> _applyRideOfferResolutions(
  Ref ref,
  List<ProviderRequestResolution> resolutions,
) async {
  await consumeProviderRideOfferResolutions(
    resolutions: resolutions,
    dismiss: (resolution) {
      final rideId = resolution.rideId;
      final reason = resolution.resolutionReason ?? 'resolved';
      final visibleRideId = ref.read(visibleRideRequestIdProvider);
      final incomingRideId = ref.read(incomingRideRequestProvider)?.id;
      if (visibleRideId == rideId || incomingRideId == rideId) {
        ref.read(rideOfferDismissalProvider.notifier).state =
            RideOfferDismissal(
          rideId: rideId,
          reason: reason,
        );
        if (incomingRideId == rideId) {
          ref.read(incomingRideRequestProvider.notifier).state = null;
        }
      }
      ref
          .read(rideRequestDeadlineByIdProvider.notifier)
          .update((deadlines) => {...deadlines}..remove(rideId));
      ref
          .read(rideOfferIdByRideProvider.notifier)
          .update((offers) => {...offers}..remove(rideId));
    },
    consume: (resolution) async {
      final reason = resolution.resolutionReason ?? 'resolved';
      await clearIncomingRequestAlert(
        type: NotificationPayload.typeRideRequest,
        requestId: resolution.rideId,
        offerId: resolution.offerId,
        reason: reason,
      );
      await clearStoredRideOffer(resolution.offerId);
    },
    claimNotice: claimRideOfferResolutionInAppNotice,
    showNotice: (message) {
      final router = ref.read(goRouterProvider);
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 5),
            ),
          );
      }
    },
  );
  return resolutions
      .where((resolution) => resolution.kind == ProviderRequestKind.ride)
      .map((resolution) => resolution.rideId)
      .toSet();
}

@visibleForTesting
Future<void> consumeProviderRideOfferResolutions({
  required List<ProviderRequestResolution> resolutions,
  required void Function(ProviderRequestResolution resolution) dismiss,
  required Future<void> Function(ProviderRequestResolution resolution) consume,
  required bool Function(String rideId) claimNotice,
  required void Function(String message) showNotice,
}) async {
  var noticeShown = false;
  for (final resolution in resolutions) {
    if (resolution.kind != ProviderRequestKind.ride) continue;
    dismiss(resolution);
    await consume(resolution);

    final message = providerOfferCancellationMessage(
      reason: resolution.resolutionReason,
      cancelledBy: resolution.cancelledBy,
    );
    if (!noticeShown && message != null && claimNotice(resolution.rideId)) {
      showNotice(message);
      noticeShown = true;
    }
  }
}

@visibleForTesting
bool shouldApplyGenericPendingRideDismissal({
  required String? visibleRideId,
  required Set<String> resolvedRideIds,
}) =>
    visibleRideId != null &&
    visibleRideId.isNotEmpty &&
    !resolvedRideIds.contains(visibleRideId);

/// Resolves a pending request only while the same request still has no other
/// UI owner.
///
/// Notification taps, sockets, and foreground recovery can all start in the
/// same resume frame. The eligibility check must therefore run both before and
/// after the asynchronous fetch. Once the second check succeeds, the caller
/// publishes synchronously so no competing callback can interleave.
@visibleForTesting
Future<bool> resolveAndClaimPendingRequestForSurface<T>({
  required bool Function() isEligible,
  required Future<T?> Function() resolve,
  required void Function(T request) claim,
}) async {
  if (!isEligible()) return false;
  final request = await resolve();
  if (request == null || !isEligible()) return false;

  // Keep the final eligibility check and ownership publication in the same
  // synchronous turn. Returning the resolved object to the caller first would
  // introduce a microtask gap in which a notification callback could claim
  // and navigate the same request.
  claim(request);
  return true;
}

bool _canSurfaceRideRequest(Ref ref, String rideId) {
  final router = ref.read(goRouterProvider);
  if (router.routerDelegate.currentConfiguration.uri.path == '/ride-request') {
    return false;
  }
  if (ref.read(activeRideProvider).ride?.id == rideId) return false;
  if (ref.read(incomingRideRequestProvider)?.id == rideId) return false;
  if (ref.read(visibleRideRequestIdProvider) == rideId) return false;
  if (ref.read(rideRequestNavigationInFlightProvider).contains(rideId)) {
    return false;
  }
  return !ref.read(surfacedRideIdsProvider).contains(rideId);
}

Future<void> _surfaceRideRequest(
  Ref ref,
  ProviderPendingRequest request,
) async {
  try {
    await resolveAndClaimPendingRequestForSurface<Ride>(
      isEligible: () => _canSurfaceRideRequest(ref, request.id),
      resolve: () => _readPendingRide(
        request,
        ref.read(rideServiceProvider).getRide,
      ),
      claim: (ride) {
        if (request.expiresAt != null) {
          ref.read(rideRequestDeadlineByIdProvider.notifier).update(
                (m) => {...m, ride.id: request.expiresAt!},
              );
        }
        if (request.offerId != null && request.offerId!.isNotEmpty) {
          ref.read(rideOfferIdByRideProvider.notifier).update(
                (offers) => {...offers, ride.id: request.offerId!},
              );
        }
        ref
            .read(surfacedRideIdsProvider.notifier)
            .update((s) => {...s, ride.id});
        ref.read(incomingRideRequestProvider.notifier).state = null;
        ref.read(incomingRideRequestProvider.notifier).state = ride;
        ref.read(navBadgeProvider.notifier).increment('/home');
      },
    );
  } catch (e) {
    debugPrint('[PendingRequestRecovery] ride ${request.id} failed: $e');
  }
}

Future<Ride?> _readPendingRide(
  ProviderPendingRequest request,
  Future<Map<String, dynamic>> Function(String rideId) fetchRide,
) async {
  final payload = request.payload.isNotEmpty
      ? request.payload
      : await fetchRide(request.id).timeout(const Duration(seconds: 8));
  final ride = Ride.fromJson(payload);
  if (ride.status != RideStatus.requested) return null;
  return ride;
}

Future<void> _surfaceJobRequest(
  Ref ref,
  ProviderPendingRequest request, {
  required AuthSessionIdentity expectedSession,
}) async {
  try {
    final resolved = await resolvePendingJobRequestForSurface(
      request: request,
      acknowledge: (payload) => acknowledgeJobOffer(
        payload: payload,
        jobs: ref.read(jobServiceProvider),
      ),
      fetchJob: ref.read(jobServiceProvider).getJob,
    );
    if (resolved == null) return;
    if (ref.read(currentAuthSessionIdentityProvider) != expectedSession) return;
    final job = resolved.job;
    final offerId = resolved.offerId;
    if (job.status != JobStatus.open && job.status != JobStatus.adminAssigned) {
      return;
    }

    // Receipt/hydration yields to socket and FCM. Use the state that exists
    // after that await so recovery cannot double-surface their winning copy.
    final previouslySurfaced =
        ref.read(surfacedJobIdsProvider).contains(job.id);
    final previousExact = ref.read(lastJobOfferIdByJobProvider)[job.id];
    final disposition = jobOfferSurfaceDisposition(
      jobAlreadySurfaced: previouslySurfaced,
      lastExactOfferId: previousExact,
      incomingOfferId: offerId,
    );
    if (offerId != null && offerId.isNotEmpty) {
      ref.read(jobOfferIdByJobProvider.notifier).update(
            (offers) => {...offers, job.id: offerId},
          );
      ref.read(lastJobOfferIdByJobProvider.notifier).update(
            (offers) => {...offers, job.id: offerId},
          );
    }
    final deadline = resolved.decisionExpiresAt;
    if (deadline != null) {
      ref.read(jobOfferDeadlineByJobProvider.notifier).update(
            (deadlines) => {...deadlines, job.id: deadline},
          );
    }
    if (previousExact != offerId) {
      // A terminal tombstone for offer A may have published a dismissal
      // immediately before this recovery response's fresh offer B. Clear it
      // before exposing B so the old screen's deferred pop cannot win.
      ref.read(jobOfferDismissalProvider.notifier).state = null;
    }
    ref.read(surfacedJobIdsProvider.notifier).update((s) => {...s, job.id});
    ref.read(pendingIncomingJobsProvider.notifier).enqueue(job);
    if (ref.read(visibleJobRequestIdProvider) == job.id ||
        ref.read(visibleJobModalIdProvider) == job.id) {
      return;
    }
    if (disposition != JobOfferSurfaceDisposition.surface) return;
    ref.read(incomingJobRequestProvider.notifier).state = null;
    ref.read(incomingJobRequestProvider.notifier).state = job;
    ref.read(navBadgeProvider.notifier).increment('/trips');
  } catch (e) {
    debugPrint('[PendingRequestRecovery] job ${request.id} failed: $e');
  }
}

@visibleForTesting
class PendingJobForSurface {
  const PendingJobForSurface({
    required this.job,
    this.offerId,
    this.decisionExpiresAt,
  });

  final Job job;
  final String? offerId;
  final DateTime? decisionExpiresAt;
}

/// Resolves one recovered job through the same durable v2 receipt gate used
/// by socket and FCM delivery. Receipt failures return null without calling a
/// decline endpoint; the persisted identity remains available for a later
/// recovery attempt or exact terminal tombstone.
@visibleForTesting
Future<PendingJobForSurface?> resolvePendingJobRequestForSurface({
  required ProviderPendingRequest request,
  required Future<ReceivedJobOffer?> Function(Map<String, dynamic> payload)
      acknowledge,
  required Future<Map<String, dynamic>> Function(String jobId) fetchJob,
}) async {
  var authoritativeDeadline = request.expiresAt;
  var offerId = request.offerId;
  var serverPayload = request.payload;
  final receiptPayload = <String, dynamic>{
    ...serverPayload,
    'jobId': request.id,
    if (offerId != null) 'offerId': offerId,
    if (request.offerVersion != null)
      'offerVersion': request.offerVersion.toString(),
    if (authoritativeDeadline != null)
      'expiresAt': authoritativeDeadline.toIso8601String(),
  };
  if (isReceiptJobOffer(receiptPayload)) {
    final received = await acknowledge(receiptPayload);
    if (received == null || !received.hasExactReceipt) return null;
    serverPayload = received.payload;
    offerId = received.offerId;
    authoritativeDeadline = received.decisionExpiresAt;
  }

  Map<String, dynamic> payloadWithDeadline(Map<String, dynamic> payload) => {
        ...payload,
        'jobId': request.id,
        if (authoritativeDeadline != null)
          'expiresAt': authoritativeDeadline.toIso8601String(),
      };

  try {
    return PendingJobForSurface(
      job: Job.fromJson(payloadWithDeadline(serverPayload)),
      offerId: offerId,
      decisionExpiresAt: authoritativeDeadline,
    );
  } catch (_) {
    final hydrated = await fetchJob(request.id);
    return PendingJobForSurface(
      job: Job.fromJson(
        payloadWithDeadline(<String, dynamic>{
          ...hydrated,
          ...serverPayload,
        }),
      ),
      offerId: offerId,
      decisionExpiresAt: authoritativeDeadline,
    );
  }
}
