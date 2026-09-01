import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/app_lifecycle_provider.dart';
import '../../../core/providers/nav_badge_provider.dart';
import '../../../core/providers/socket_provider.dart';
import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../../core/providers/provider_status_provider.dart';
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
/// While the artisan is online, polls `GET /jobs` every 10s. Open jobs
/// created **after** the artisan came online and not yet surfaced are
/// pushed into the same provider the socket writes to, which triggers the
/// standard modal flow. Jobs that existed before the artisan came online
/// are silently marked surfaced (the artisan came in too late to live-bid
/// on them — they're still visible in the marketplace browse).
///
/// Older designs seeded [surfacedJobIdsProvider] from the first poll
/// response, but that swallowed any job created during the seed window:
/// the seed query's `GET /jobs` returned the just-created job, marked it
/// "seen", and every subsequent socket re-broadcast / poll hit the dedup
/// silently. Symptom: artisan had to re-trigger several jobs before any
/// modal popped. The `createdAt` cutoff is the fix.
final jobPollerProvider = Provider<void>((ref) {
  final status = ref.watch(providerStatusProvider);
  final isArtisan = ref.watch(providerTypeProvider).isArtisan;
  if (!status.isOnline || !isArtisan) return;

  final jobService = ref.read(jobServiceProvider);
  final goOnlineAt = DateTime.now().toUtc();
  Timer? timer;
  var pollInFlight = false;
  var active = true;

  Future<List<Job>> fetchOpenJobs() async {
    final raw = await jobService.listJobs(page: 1, limit: 50, status: 'open');
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

  Future<void> poll() async {
    if (!active || pollInFlight) return;
    pollInFlight = true;
    try {
      final jobs = await fetchOpenJobs();
      if (!active) return;
      final surfaced = ref.read(surfacedJobIdsProvider);

      final fresh = <Job>[];
      final preExisting = <Job>[];
      for (final j in jobs) {
        if (surfaced.contains(j.id)) continue;
        final created = _parseIso(j.createdAt);
        // Treat unknown timestamps as fresh — better to over-show one stale
        // modal the artisan can dismiss than to silently drop a real job
        // because the backend regressed and stopped sending `createdAt`.
        if (created != null && created.isBefore(goOnlineAt)) {
          preExisting.add(j);
        } else {
          fresh.add(j);
        }
      }

      if (preExisting.isNotEmpty) {
        ref
            .read(surfacedJobIdsProvider.notifier)
            .update((s) => {...s, ...preExisting.map((j) => j.id)});
      }

      if (fresh.isEmpty) return;

      debugPrint('[JobPoller] found ${fresh.length} new open job(s)');

      // Mark all as surfaced up front so a poll racing with the socket
      // doesn't double-fire.
      ref
          .read(surfacedJobIdsProvider.notifier)
          .update((s) => {...s, ...fresh.map((j) => j.id)});

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
    } finally {
      pollInFlight = false;
    }
  }

  void start() {
    if (timer != null) return;
    debugPrint('[JobPoller] starting');
    // Poll immediately so a job created in the moments between the artisan
    // tapping online (or the app coming back to foreground) and the
    // timer's first tick still surfaces.
    poll();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => poll());
  }

  void stop() {
    if (timer == null) return;
    debugPrint('[JobPoller] paused');
    timer!.cancel();
    timer = null;
  }

  // Gate the timer on app foreground. Polling while backgrounded is
  // pointless on Android (Doze blocks DNS/network) and burns battery
  // for nothing — FCM is the wakeup channel for incoming jobs while
  // the app is suspended. `goOnlineAt` is captured once at the top so
  // jobs created during a background interval are flagged "fresh"
  // (not preExisting) on the next poll after resume.
  if (ref.read(appForegroundedProvider)) {
    start();
  }
  ref.listen<bool>(appForegroundedProvider, (_, isForegrounded) {
    if (isForegrounded) {
      start();
    } else {
      stop();
    }
  });

  ref.onDispose(() {
    active = false;
    debugPrint('[JobPoller] stopped');
    timer?.cancel();
  });
});

DateTime? _parseIso(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
