import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/artisan_home/widgets/incoming_job_modal.dart';
import '../../features/artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
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
class IncomingRequestListener extends ConsumerWidget {
  const IncomingRequestListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return child;
  }

  void _goToRideRequest(BuildContext context, Ride ride, WidgetRef ref) {
    // Clear the incoming state so the listener doesn't re-trigger on rebuild.
    ref.read(incomingRideRequestProvider.notifier).state = null;
    context.push('/ride-request', extra: ride);
  }

  void _showJobModal(BuildContext context, Job job, WidgetRef ref) {
    // Clear the incoming state so the listener doesn't re-trigger on rebuild.
    ref.read(incomingJobRequestProvider.notifier).state = null;

    // Persist the job so the artisan can re-open it from the My Jobs → New
    // tab if they accidentally dismiss the modal.
    ref.read(pendingIncomingJobsProvider.notifier).enqueue(job);
    ref.read(navBadgeProvider.notifier).increment('/trips');

    // Compute distance from the artisan's last known GPS fix (best-effort).
    final position = ref.read(driverLocationStreamProvider).valueOrNull;
    final distanceKm = position != null
        ? Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              job.latitude,
              job.longitude,
            ) /
            1000
        : null;

    IncomingJobModal.show(
      context,
      job: job,
      distanceKm: distanceKm,
    );
  }
}
