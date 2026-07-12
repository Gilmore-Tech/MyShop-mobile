import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../app/router.dart' show goRouterProvider;
import '../../features/artisan_home/providers/job_poller_provider.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../di/providers.dart';
import 'app_lifecycle_provider.dart';
import 'nav_badge_provider.dart';
import 'socket_provider.dart';

Future<void>? _recoveryInFlight;
DateTime? _lastRecoveryStartedAt;

/// Reconciles provider-targeted ride/job requests that arrived while the app
/// was backgrounded, terminated, or opened manually instead of via a push tap.
///
/// Socket events are still the low-latency path. This is the safety net that
/// prevents a push tap from landing on a blank/home screen when the in-memory
/// request payload was lost during process sleep.
final pendingRequestRecoveryBridgeProvider = Provider<void>((ref) {
  final auth = ref.watch(authControllerProvider);
  final foregrounded = ref.watch(appForegroundedProvider);
  if (auth is! AuthAuthenticated || !foregrounded) return;
  _schedulePendingRequestRecovery(ref);
});

void _schedulePendingRequestRecovery(Ref ref) {
  if (_recoveryInFlight != null) return;
  final now = DateTime.now();
  final last = _lastRecoveryStartedAt;
  if (last != null && now.difference(last) < const Duration(seconds: 5)) {
    return;
  }
  _lastRecoveryStartedAt = now;
  _recoveryInFlight = _recoverPendingRequests(ref).whenComplete(() {
    _recoveryInFlight = null;
  });
}

Future<void> recoverPendingRequestsNow(Ref ref) => _recoverPendingRequests(ref);

/// Fetch the first still-actionable pending ride request without relying on
/// the shell-level IncomingRequestListener. Used by the /ride-request fallback
/// route during notification/cold-start timing gaps: that route sits outside
/// the shell, so setting [incomingRideRequestProvider] alone would not surface
/// the real request.
Future<Ride?> recoverPendingRideRequest(WidgetRef ref) async {
  try {
    final requests = await ref
        .read(providerRequestServiceProvider)
        .listPendingRequests()
        .timeout(const Duration(seconds: 10));
    for (final request in requests) {
      if (request.kind != ProviderRequestKind.ride) continue;
      final ride = await _readPendingRide(
        request,
        ref.read(rideServiceProvider).getRide,
      );
      if (ride != null && request.expiresAt != null) {
        ref.read(rideRequestDeadlineByIdProvider.notifier).update(
              (m) => {...m, ride.id: request.expiresAt!},
            );
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
    final requests = await ref
        .read(providerRequestServiceProvider)
        .listPendingRequests()
        .timeout(const Duration(seconds: 10));
    if (requests.isEmpty) return;

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
