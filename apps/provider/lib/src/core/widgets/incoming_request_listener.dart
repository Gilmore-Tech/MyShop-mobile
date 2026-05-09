import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_utils/shared_utils.dart';

import '../../features/artisan_home/widgets/incoming_job_modal.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/driver_home/providers/ride_request_provider.dart';
import '../providers/nav_badge_provider.dart';
import '../providers/socket_provider.dart';
import '../services/local_notification_service.dart';

/// A transparent widget that listens for incoming ride/job requests via
/// Socket.IO and surfaces them to the user.
///
/// - **Jobs:** opens a bottom-sheet modal with condensed details and a
///   "View Details" CTA. Plays haptic + alert sound on arrival.
/// - **Rides:** pushes the full ride request screen (drivers act faster
///   than artisans, so no intermediate sheet).
///
/// Mount this inside the shell so incoming requests pop up from any tab.
class IncomingRequestListener extends ConsumerStatefulWidget {
  const IncomingRequestListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingRequestListener> createState() =>
      _IncomingRequestListenerState();
}

class _IncomingRequestListenerState
    extends ConsumerState<IncomingRequestListener> {
  /// Tracks whether we've routed for the *currently-recovered* active
  /// ride. Reset to false when [activeRideProvider] goes back to null so
  /// a new recovery (after the user completes/cancels the previous one)
  /// can route again.
  bool _routedForCurrentActiveRide = false;

  @override
  void initState() {
    super.initState();
    // Cold-start race guard: the recovery bridge in main.dart fires
    // tryRecover() the moment auth flips to authenticated. If the GET
    // returns before this widget mounts, [activeRideProvider] is already
    // populated and `ref.listen` below — which only fires on subsequent
    // transitions, never on the initial registered value — silently
    // misses it. Check the current state once after the first frame and
    // route if needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ride = ref.read(activeRideProvider).ride;
      if (ride != null) {
        _maybeRouteToActiveRide(ride);
      }
      // Same race for jobs: a `job:new` (or poller find) that landed
      // while the listener was unmounted — e.g. while the artisan was
      // on /active-job, /job-request, or any non-shell route — leaves
      // the state populated but `ref.listen` won't fire on the initial
      // value when the shell remounts. Surface it now.
      final pendingJob = ref.read(incomingJobRequestProvider);
      if (pendingJob != null) {
        _showJobModal(context, pendingJob, ref);
      }
    });
  }

  void _maybeRouteToActiveRide(Ride ride) {
    if (_routedForCurrentActiveRide) return;
    if (!mounted) return;
    final currentLocation = GoRouterState.of(context).matchedLocation;
    if (currentLocation == '/active-ride' ||
        currentLocation == '/ride-request') {
      // We're already on the right screen — flip the flag so we don't
      // try to re-route on the next state change for the same ride.
      _routedForCurrentActiveRide = true;
      return;
    }
    debugPrint('[IncomingRequestListener] active ride ${ride.id} '
        '(status=${ride.status}) — routing to /active-ride');
    _routedForCurrentActiveRide = true;
    context.go('/active-ride');
  }

  @override
  Widget build(BuildContext context) {
    // Listen for new ride requests (driver)
    ref.listen<Ride?>(incomingRideRequestProvider, (prev, next) {
      debugPrint(
        '[IncomingRequestListener] ride event: prev=${prev?.id} next=${next?.id}',
      );
      // Pop up whenever a non-null ride lands in the provider. The handler
      // clears the state to null immediately after, so duplicate fires for
      // the same id don't happen in practice.
      if (next != null) {
        LocalNotificationService.instance.playForegroundAlert();
        _goToRideRequest(context, next, ref);
      }
    });

    // Surface a recovered (or freshly-accepted) active ride. The recovery
    // bridge populates [activeRideProvider] from `GET /drivers/me/active-
    // ride`; the live accept flow does its own pushReplacement so we
    // gate on the current location below.
    ref.listen<ActiveRideState>(activeRideProvider, (prev, next) {
      // Reset the routing latch when the slot empties — completing or
      // cancelling a ride should let the next recovery re-route.
      if (next.ride == null) {
        _routedForCurrentActiveRide = false;
        return;
      }
      // Reset the latch if the user navigated off /active-ride (e.g.
      // background→foreground landed them on /home). Without this, an
      // active ride that came back through ref.listen but didn't trigger
      // a state change couldn't be recovered.
      if (mounted) {
        final loc = GoRouterState.of(context).matchedLocation;
        if (loc != '/active-ride' && loc != '/ride-request') {
          _routedForCurrentActiveRide = false;
        }
      }
      // Only act on the null → non-null transition. Status updates within
      // an already-active ride are handled inside the active-ride screen
      // itself.
      final hadRide = prev?.ride != null;
      if (hadRide) return;
      _maybeRouteToActiveRide(next.ride!);
    });

    // Listen for new job requests (artisan)
    ref.listen<Job?>(incomingJobRequestProvider, (prev, next) {
      debugPrint(
        '[IncomingRequestListener] job event: prev=${prev?.id} next=${next?.id}',
      );
      if (next != null) {
        LocalNotificationService.instance.playForegroundAlert();
        _showJobModal(context, next, ref);
      }
    });

    return widget.child;
  }

  void _goToRideRequest(BuildContext context, Ride ride, WidgetRef ref) {
    // Clear the incoming state so the listener doesn't re-trigger on rebuild.
    ref.read(incomingRideRequestProvider.notifier).state = null;
    context.push('/ride-request', extra: ride);
  }

  void _showJobModal(BuildContext context, Job job, WidgetRef ref) {
    debugPrint('[IncomingRequestListener] _showJobModal start id=${job.id} '
        'mounted=${context.mounted}');

    // Clear the incoming state so the listener doesn't re-trigger on rebuild.
    ref.read(incomingJobRequestProvider.notifier).state = null;

    // Persist the job so the artisan can re-open it from the My Jobs → New
    // tab if they accidentally dismiss the modal.
    ref.read(pendingIncomingJobsProvider.notifier).enqueue(job);
    ref.read(navBadgeProvider.notifier).increment('/trips');

    // Compute distance + straight-line ETA from the artisan's last known
    // GPS fix (best-effort — both fields stay null when no fix yet).
    final position = ref.read(driverLocationStreamProvider).valueOrNull;
    double? distanceKm;
    int? etaMinutes;
    if (position != null) {
      final meters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        job.latitude,
        job.longitude,
      );
      distanceKm = meters / 1000;
      etaMinutes = estimatedEtaMinutes(meters);
    }

    if (!context.mounted) {
      debugPrint('[IncomingRequestListener] context unmounted — skip modal');
      return;
    }

    IncomingJobModal.show(
      context,
      job: job,
      distanceKm: distanceKm,
      etaMinutes: etaMinutes,
    ).then((_) {
      debugPrint('[IncomingRequestListener] modal closed id=${job.id}');
    });
    debugPrint(
        '[IncomingRequestListener] showModalBottomSheet invoked id=${job.id}');
  }
}
