import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';

import '../providers/socket_provider.dart';

/// A transparent widget that listens for incoming ride/job requests via
/// Socket.IO and auto-navigates to the appropriate request screen with
/// haptic feedback and alert sound.
///
/// Mount this inside the shell so incoming requests pop up from any tab.
class IncomingRequestListener extends ConsumerWidget {
  const IncomingRequestListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for new ride requests (driver)
    ref.listen<Ride?>(incomingRideRequestProvider, (prev, next) {
      if (next != null && prev?.id != next.id) {
        _alert();
        _goToRideRequest(context, next, ref);
      }
    });

    // Listen for new job requests (artisan)
    ref.listen<Job?>(incomingJobRequestProvider, (prev, next) {
      if (next != null && prev?.id != next.id) {
        _alert();
        _goToJobRequest(context, next, ref);
      }
    });

    return child;
  }

  /// Trigger haptic + system alert sound to get the user's attention.
  void _alert() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  void _goToRideRequest(BuildContext context, Ride ride, WidgetRef ref) {
    // Clear the incoming state so the listener doesn't re-trigger on rebuild.
    ref.read(incomingRideRequestProvider.notifier).state = null;
    // Use push so the user can dismiss back to where they were.
    context.push('/ride-request', extra: ride);
  }

  void _goToJobRequest(BuildContext context, Job job, WidgetRef ref) {
    ref.read(incomingJobRequestProvider.notifier).state = null;
    context.push('/job-request', extra: job);
  }
}
