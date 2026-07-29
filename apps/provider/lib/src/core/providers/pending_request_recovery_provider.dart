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
Future<Ride?> recoverPendingRideRequest(WidgetRef ref) {
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

Future<Ride?> recoverPendingRideRequestById(WidgetRef ref, String rideId) {
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
    final recovery = await fetchProviderRequestRecovery(
      readStoredOffers: readStoredRideOfferIdentities,
      recover: (knownOfferIds) => ref
          .read(providerRequestServiceProvider)
          .recoverPendingRequests(knownOfferIds: knownOfferIds)
          .timeout(const Duration(seconds: 10)),
    );
    if (recovery == null) return;
    final resolvedRideIds =
        await _applyRideOfferResolutions(ref, recovery.resolutions);
    final requests = recovery.requests;
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
          if (onJobRequest) continue;
          await _surfaceJobRequest(ref, request);
          return;
      }
    }
  } catch (e) {
    debugPrint('[PendingRequestRecovery] failed: $e');
  }
}

/// Reads durable identities and asks the server for their exact state without
/// consuming any local identity on a transient fetch failure.
@visibleForTesting
Future<ProviderRequestRecoveryResult?> fetchProviderRequestRecovery({
  required Future<List<StoredRideOfferIdentity>> Function() readStoredOffers,
  required Future<ProviderRequestRecoveryResult> Function(
    List<String> knownOfferIds,
  ) recover,
}) async {
  try {
    final storedOffers = await readStoredOffers();
    return await recover(
      storedOffers
          .map((identity) => identity.offerId)
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

Future<void> _surfaceRideRequest(
  Ref ref,
  ProviderPendingRequest request,
) async {
  try {
    final active = ref.read(activeRideProvider).ride;
    if (active != null && active.id == request.id) return;
    if (ref.read(visibleRideRequestIdProvider) == request.id) return;
    if (ref.read(rideRequestNavigationInFlightProvider).contains(request.id)) {
      return;
    }
    if (ref.read(surfacedRideIdsProvider).contains(request.id)) return;

    final ride = await _readPendingRide(
      request,
      ref.read(rideServiceProvider).getRide,
    );
    if (ride == null) return;

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
    ref.read(surfacedRideIdsProvider.notifier).update((s) => {...s, ride.id});
    ref.read(incomingRideRequestProvider.notifier).state = null;
    ref.read(incomingRideRequestProvider.notifier).state = ride;
    ref.read(navBadgeProvider.notifier).increment('/home');
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
      : await fetchRide(request.id);
  final ride = Ride.fromJson(payload);
  if (ride.status != RideStatus.requested) return null;
  return ride;
}

Future<void> _surfaceJobRequest(Ref ref, ProviderPendingRequest request) async {
  try {
    final payload = request.payload.isNotEmpty
        ? request.payload
        : await ref.read(jobServiceProvider).getJob(request.id);
    final job = Job.fromJson(payload);
    if (job.status != JobStatus.open && job.status != JobStatus.adminAssigned) {
      return;
    }

    ref.read(surfacedJobIdsProvider.notifier).update((s) => {...s, job.id});
    ref.read(pendingIncomingJobsProvider.notifier).enqueue(job);
    ref.read(incomingJobRequestProvider.notifier).state = null;
    ref.read(incomingJobRequestProvider.notifier).state = job;
    ref.read(navBadgeProvider.notifier).increment('/trips');
  } catch (e) {
    debugPrint('[PendingRequestRecovery] job ${request.id} failed: $e');
  }
}
