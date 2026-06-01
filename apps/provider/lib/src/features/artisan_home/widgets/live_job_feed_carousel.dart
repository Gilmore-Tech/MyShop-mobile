import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/last_known_position_provider.dart';
import '../providers/live_job_feed_provider.dart';
import 'live_feed_snapshot_card.dart';

/// Auto-scrolling, looping carousel of [LiveFeedSnapshotCard]s for the
/// artisan-home "Live Job Feed" section.
///
/// Renders nothing when the feed is empty so the parent screen can fall
/// back to its existing empty-state placeholder. Auto-advances every
/// [_kAdvanceInterval] (3s) with a 350ms ease transition and pauses for
/// [_kResumeDelay] (5s) after the user manually swipes.
class LiveJobFeedCarousel extends ConsumerStatefulWidget {
  const LiveJobFeedCarousel({super.key});

  static const double height = 140;
  static const _kAdvanceInterval = Duration(seconds: 3);
  static const _kResumeDelay = Duration(seconds: 5);
  static const _kAnimDuration = Duration(milliseconds: 350);
  static const _kViewportFraction = 0.85;

  @override
  ConsumerState<LiveJobFeedCarousel> createState() =>
      _LiveJobFeedCarouselState();
}

class _LiveJobFeedCarouselState extends ConsumerState<LiveJobFeedCarousel> {
  final PageController _controller =
      PageController(viewportFraction: LiveJobFeedCarousel._kViewportFraction);
  Timer? _advanceTimer;
  Timer? _resumeTimer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoAdvance() {
    _advanceTimer?.cancel();
    _advanceTimer = Timer.periodic(LiveJobFeedCarousel._kAdvanceInterval, (_) {
      final items = ref.read(liveJobFeedProvider);
      if (items.length < 2 || !_controller.hasClients) return;
      final next = (_page + 1) % items.length;
      _controller
          .animateToPage(
        next,
        duration: LiveJobFeedCarousel._kAnimDuration,
        curve: Curves.easeInOut,
      )
          .catchError((_) {
        // Best-effort — the controller might be detached mid-animation
        // during a hot reload; ignore.
      });
    });
  }

  void _pauseForUser() {
    _advanceTimer?.cancel();
    _resumeTimer?.cancel();
    _resumeTimer = Timer(LiveJobFeedCarousel._kResumeDelay, _startAutoAdvance);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(liveJobFeedProvider);
    if (items.isEmpty) return const SizedBox.shrink();

    final positionAsync = ref.watch(lastKnownPositionProvider);
    final myLat = positionAsync.value?.latitude;
    final myLng = positionAsync.value?.longitude;

    return SizedBox(
      height: LiveJobFeedCarousel.height,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is UserScrollNotification) _pauseForUser();
          return false;
        },
        child: PageView.builder(
          controller: _controller,
          itemCount: items.length,
          padEnds: false,
          onPageChanged: (i) => _page = i,
          itemBuilder: (_, i) {
            final job = items[i];
            final distanceKm = (myLat != null && myLng != null)
                ? _haversineKm(myLat, myLng, job.latitude, job.longitude)
                : null;
            return Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? MyShopSpacing.md : 0,
                right: MyShopSpacing.sm,
              ),
              child: LiveFeedSnapshotCard(
                categoryName: job.categoryName,
                areaLabel: job.areaLabel,
                timeAgo: _timeAgo(job.createdAt),
                distanceKm: distanceKm,
              ),
            );
          },
        ),
      ),
    );
  }
}

String _timeAgo(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} d ago';
}

/// Great-circle distance in km — same formula used elsewhere in the app.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

double _deg2rad(double d) => d * math.pi / 180.0;
