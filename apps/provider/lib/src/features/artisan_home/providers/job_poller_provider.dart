import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/nav_badge_provider.dart';
import '../../../core/providers/socket_provider.dart';
import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../driver_home/providers/driver_status_provider.dart';
import '../../profile/providers/provider_type_provider.dart';

/// Set of job IDs already surfaced to the artisan (via socket OR poller).
///
/// Both the socket handler and the REST poller consult this before pushing
/// a job into [incomingJobRequestProvider] so the artisan never gets two
/// modals for the same job.
///
/// Persistent across online/offline toggles — clearing is intentional on
/// logout only.
final surfacedJobIdsProvider = StateProvider<Set<String>>((_) => <String>{});

/// REST-polling fallback for incoming jobs.
///
/// The socket is the primary delivery channel — this poller is the safety
/// net for the edge cases where it silently fails (zombie connection after
/// backgrounding, stale token on reconnect, network transport hiccups).
///
/// While the artisan is online, polls `GET /jobs` every 10s. Any open job
/// that hasn't been surfaced yet is pushed into the same provider the
/// socket writes to, which triggers the standard modal flow.
///
/// On first activation, seeds [surfacedJobIdsProvider] with the current
/// open jobs so the artisan isn't flooded with modals for jobs posted
/// before they came online.
final jobPollerProvider = Provider<void>((ref) {
  final status = ref.watch(driverStatusProvider);
  final isArtisan = ref.watch(providerTypeProvider).isArtisan;
  if (!status.isOnline || !isArtisan) return;

  final jobService = ref.read(jobServiceProvider);

  Future<List<Job>> fetchOpenJobs() async {
    final raw = await jobService.listJobs(
      page: 1,
      limit: 50,
      status: 'open',
    );
    final jobs = <Job>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final job = Job.fromJson(item);
        // Defensive: some backends return the filter as a hint, not a hard
        // guarantee. Drop anything that isn't actually open.
        if (job.status != JobStatus.open) continue;
        jobs.add(job);
      } catch (e) {
        debugPrint('[JobPoller] skip unparseable entry: $e');
      }
    }
    return jobs;
  }

  Future<void> poll({required bool isSeed}) async {
    try {
      final jobs = await fetchOpenJobs();
      final surfaced = ref.read(surfacedJobIdsProvider);

      if (isSeed) {
        // First run after going online — mark everything currently open as
        // already-seen. Anything that appears in subsequent polls is
        // genuinely new and triggers the modal path.
        if (jobs.isEmpty) return;
        ref.read(surfacedJobIdsProvider.notifier).update(
              (s) => {...s, ...jobs.map((j) => j.id)},
            );
        debugPrint(
          '[JobPoller] seed — marked ${jobs.length} existing open jobs as seen',
        );
        return;
      }

      final fresh =
          jobs.where((j) => !surfaced.contains(j.id)).toList(growable: false);
      if (fresh.isEmpty) return;

      debugPrint('[JobPoller] found ${fresh.length} new open job(s)');

      // Mark all as surfaced up front so a poll racing with the socket
      // doesn't double-fire.
      ref.read(surfacedJobIdsProvider.notifier).update(
            (s) => {...s, ...fresh.map((j) => j.id)},
          );

      // Trigger the modal for the most recent (first). Rest go straight
      // into the pending queue so they show up in the "New" tab — avoids
      // stacking modals on top of each other.
      final first = fresh.first;
      ref.read(incomingJobRequestProvider.notifier).state = null;
      ref.read(incomingJobRequestProvider.notifier).state = first;
      ref.read(navBadgeProvider.notifier).increment('/home');

      for (final j in fresh.skip(1)) {
        ref.read(pendingIncomingJobsProvider.notifier).enqueue(j);
      }
    } catch (e) {
      debugPrint('[JobPoller] poll failed: $e');
    }
  }

  // Kick off the seed immediately, then start the interval timer.
  poll(isSeed: true);
  final timer = Timer.periodic(
    const Duration(seconds: 3),
    (_) => poll(isSeed: false),
  );
  ref.onDispose(() {
    debugPrint('[JobPoller] stopped');
    timer.cancel();
  });
});
