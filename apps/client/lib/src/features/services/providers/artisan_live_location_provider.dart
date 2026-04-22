import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

/// A live (moving) position for a single artisan who has bid on a job.
/// Sourced from `GET /v1/jobs/:jobId/bids/locations` — see backend contract.
class ArtisanLiveLocation {
  final String artisanId;
  final double latitude;
  final double longitude;
  final int etaMinutes;

  const ArtisanLiveLocation({
    required this.artisanId,
    required this.latitude,
    required this.longitude,
    required this.etaMinutes,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// How often to re-hit `/bids/locations`. Backend sizes for 5–10 s.
const _livePollInterval = Duration(seconds: 10);

/// Streams a live artisan-locations map for one job. Keyed by `artisanId`.
///
/// - Emits the first fetch immediately, then re-polls every [_livePollInterval].
/// - Individual poll errors are swallowed so the stream keeps ticking — last
///   known state stays visible.
/// - Auto-disposes: timer stops the moment the last listener goes away.
///
/// Scope: watch this **only** from the widgets that actually need the live
/// coordinates (distance chip, map markers). Do not watch from the screen
/// root, otherwise the whole page rebuilds on every poll.
final artisanLiveLocationsProvider = StreamProvider.autoDispose
    .family<Map<String, ArtisanLiveLocation>, String>(
  (ref, jobId) async* {
    final jobService = ref.watch(jobServiceProvider);

    Future<Map<String, ArtisanLiveLocation>> fetch() async {
      final raw = await jobService.getBidLocations(jobId);
      final map = <String, ArtisanLiveLocation>{};
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final artisanId = item['artisanId'] as String?;
        final lat = (item['latitude'] as num?)?.toDouble();
        final lng = (item['longitude'] as num?)?.toDouble();
        if (artisanId == null || lat == null || lng == null) continue;
        map[artisanId] = ArtisanLiveLocation(
          artisanId: artisanId,
          latitude: lat,
          longitude: lng,
          etaMinutes: (item['etaMinutes'] as num?)?.toInt() ?? 0,
        );
      }
      return map;
    }

    // First emission.
    try {
      yield await fetch();
    } catch (e) {
      developer.log('bid locations: initial fetch failed — $e',
          name: 'ArtisanLiveLocations', level: 900);
      yield const {};
    }

    // Poll loop.
    while (true) {
      await Future<void>.delayed(_livePollInterval);
      try {
        yield await fetch();
      } catch (e) {
        developer.log('bid locations: poll failed — $e',
            name: 'ArtisanLiveLocations', level: 900);
        // Keep the last good emission in place; don't yield empty here.
      }
    }
  },
);

/// Convenience: the live location for a single artisan within a job. Null when
/// the map hasn't populated yet or the artisan's location is unknown right now.
final artisanLiveLocationProvider =
    Provider.autoDispose.family<ArtisanLiveLocation?, _ArtisanKey>(
  (ref, key) {
    final asyncMap = ref.watch(artisanLiveLocationsProvider(key.jobId));
    return asyncMap.whenOrNull(data: (m) => m[key.artisanId]);
  },
);

typedef _ArtisanKey = ({String jobId, String artisanId});

/// Public key helper so callers don't have to spell the record shape.
({String jobId, String artisanId}) artisanLiveKey({
  required String jobId,
  required String artisanId,
}) =>
    (jobId: jobId, artisanId: artisanId);
