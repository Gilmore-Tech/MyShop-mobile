import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/chat/chat_entry_button.dart';
import '../../../core/providers/socket_provider.dart' show ratingSheetShownFor;
import '../../../core/services/directions_service.dart';
import '../../../core/services/nav_guidance.dart';
import '../../driver_home/providers/driver_location_provider.dart';
import '../providers/active_job_provider.dart';
import '../widgets/rate_client_sheet.dart';

/// Active job — map-first navigation view the artisan sees after accepting
/// a bid. Drives the en_route → arrived → in_progress → marked_complete
/// transitions against the backend via [ActiveJobNotifier].
///
/// PRD 5.3 — navigate to client, mark arrived/in_progress/complete, chat/call.
class ActiveJobScreen extends ConsumerStatefulWidget {
  const ActiveJobScreen({super.key});

  @override
  ConsumerState<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends ConsumerState<ActiveJobScreen> {
  /// Live distance/ETA pushed up from [_NavigationMap] on each GPS fix.
  /// The header reads it via [ValueListenableBuilder] so the text ticks
  /// down without forcing the GoogleMap to rebuild.
  final ValueNotifier<_LiveMetrics> _liveMetrics =
      ValueNotifier<_LiveMetrics>(const _LiveMetrics());

  /// Lets the parent screen ask the map to recenter without holding the
  /// GoogleMapController itself — keeps native resources scoped to the map
  /// widget.
  final _MapHandle _mapHandle = _MapHandle();

  /// One-shot guard so we don't PATCH `artisan_en_route` more than once per
  /// mount. The notifier also short-circuits, but this avoids the function
  /// call entirely and prevents any chance of a tight loop.
  bool _hasAutoStartedEnRoute = false;

  /// One-shot guard so the artisan→client rating sheet only auto-opens
  /// once when the job settles to `completed`. Without it a rebuild during
  /// the sheet's open animation would queue another sheet underneath, and
  /// the socket reconciler can also re-emit the same status.
  bool _rateSheetShown = false;

  /// Polls `GET /jobs/:id` whenever the screen is parked in a state that
  /// depends on a backend-driven transition we might miss over the
  /// socket. Two distinct cases share the timer:
  ///
  ///   - `artisan_marked_complete` with no `clientPaymentAcknowledgedAt`
  ///     yet: waiting on `job:client_payment_acknowledged` so the
  ///     "Yes, I received payment" CTA enables for Cash.
  ///   - `pending_payment`: client picked an in-app method and the
  ///     Paystack webhook will flip the job to `completed` — without
  ///     this poll, a missed `job:status:changed` leaves the artisan
  ///     stranded on "Client is paying…" while the client (and FCM
  ///     notification) say the job is done.
  ///
  /// In both cases battery saver / OS socket reaping / a backgrounded app
  /// can swallow the event silently. The poll closes the gap in 5s
  /// instead of never.
  Timer? _ackPollTimer;

  @override
  void initState() {
    super.initState();
    // Kick off the very first `artisan_en_route` transition when the
    // artisan lands here from the bid-accepted banner. Runs once per mount
    // via a microtask so the state mutation doesn't happen during build.
    Future.microtask(() {
      if (!mounted || _hasAutoStartedEnRoute) return;
      final snapshot = ref.read(activeJobProvider);
      if (snapshot.hasJob && snapshot.job!.status == JobStatus.confirmed) {
        _hasAutoStartedEnRoute = true;
        ref.read(activeJobProvider.notifier).startEnRoute();
      }
    });
  }

  @override
  void dispose() {
    _ackPollTimer?.cancel();
    _liveMetrics.dispose();
    super.dispose();
  }

  /// Starts/stops the completion-poll based on the current job. Called
  /// from build() via a `ref.listen`. Idempotent — repeated calls with
  /// the same conditions don't restart the timer.
  ///
  /// Polls while we're either (a) waiting on the client to acknowledge
  /// payment from `artisan_marked_complete`, or (b) waiting on the
  /// Paystack webhook to settle a `pending_payment` charge. Both phases
  /// rely on a socket event we can miss; the poll is the safety net.
  void _syncAckPolling(Job? job) {
    final shouldPoll = job != null &&
        ((job.status == JobStatus.artisanMarkedComplete &&
                (job.clientPaymentAcknowledgedAt == null ||
                    job.clientPaymentAcknowledgedAt!.isEmpty)) ||
            job.status == JobStatus.pendingPayment);
    if (shouldPoll) {
      if (_ackPollTimer != null) return;
      // Pull once immediately so the moment the screen lands on the
      // "waiting" state we reconcile with the server, then tick at the
      // poll cadence below. Socket events (`job:client_payment_ack`,
      // `job:status:changed`) are the primary path; this is just a
      // cold-reconnect / missed-emit safety net. 5 s was triggering
      // 429 ThrottlerExceptions when combined with the jobs-list poll
      // and the location-update cadence — 12 s comfortably fits inside
      // the global limit without making the wait state feel laggy.
      ref.read(activeJobProvider.notifier).refreshFromServer();
      _ackPollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (!mounted) return;
        ref.read(activeJobProvider.notifier).refreshFromServer();
      });
    } else {
      _ackPollTimer?.cancel();
      _ackPollTimer = null;
    }
  }

  Future<void> _maybeShowRateClientSheet() async {
    if (_rateSheetShown || !mounted) return;
    final job = ref.read(activeJobProvider).job;
    if (job == null || job.id.isEmpty) return;
    // Share the dedup set with the socket `rating:prompt` handler. The
    // backend fires status:changed AND rating:prompt back-to-back when
    // a job finalises; without coordination both paths would each pop
    // a sheet — the artisan would see two stacked rating modals. The
    // first to claim the booking wins; the other becomes a no-op.
    if (!ratingSheetShownFor.add(job.id)) {
      _rateSheetShown = true;
      return;
    }
    _rateSheetShown = true;
    final firstName = (job.clientName ?? 'Client').trim().split(' ').first;
    await showRateClientSheet(
      context,
      jobId: job.id,
      clientFirstName: firstName.isEmpty ? 'Client' : firstName,
    );
    // After the rating sheet closes, take the artisan to earnings —
    // the job is done, payout is released, and there's nothing else
    // for them to do on /active-job. Mirrors the manual "Go to
    // Earnings" CTA on the completion overlay.
    if (!mounted) return;
    ref.read(activeJobProvider.notifier).clear();
    if (!mounted) return;
    context.go('/earnings');
  }

  Future<void> _launchExternalNavigation(LatLng destination) async {
    final candidates = <Uri>[
      if (Platform.isIOS)
        Uri.parse(
          'http://maps.apple.com/?daddr='
          '${destination.latitude},${destination.longitude}&dirflg=d',
        )
      else if (Platform.isAndroid)
        Uri.parse(
          'google.navigation:q=${destination.latitude},'
          '${destination.longitude}&mode=d',
        ),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${destination.latitude},${destination.longitude}'
        '&travelmode=driving',
      ),
    ];
    for (final uri in candidates) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {
        // Try the next candidate.
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open a maps app.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeJobProvider);
    final job = state.job;
    if (job == null) {
      return const _NoActiveJob();
    }

    final destination = LatLng(job.latitude, job.longitude);

    // Backend dev data sometimes lands jobs without coordinates; the model
    // defaults to (0, 0) — an island off the African coast. Mounting a
    // GoogleMap with a destination ~700 km from the artisan's GPS makes
    // the iOS Maps SDK pre-fetch tiles across the entire ocean at multiple
    // zoom levels and blows past iOS's 2 GB jetsam watermark within a
    // second. Guard the screen so an invalid destination shows a clear
    // empty state instead of a crash.
    if (!_isValidLatLng(destination)) {
      return _NoJobLocation(job: job);
    }

    // Surface notifier errors via snackbar, and auto-open the rating sheet
    // the first time the job settles to `completed`.
    ref.listen<ActiveJobState>(activeJobProvider, (prev, next) {
      if (!mounted) return;
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
      final justCompleted = next.job?.status == JobStatus.completed &&
          prev?.job?.status != JobStatus.completed;
      if (justCompleted) {
        _maybeShowRateClientSheet();
      }
      _syncAckPolling(next.job);
    });

    // Reconcile polling with the current state on first build too — the
    // listener above only fires on subsequent transitions, so without this
    // initial call we'd miss starting the poll for a job that was already
    // sitting in `artisan_marked_complete` when this screen mounted.
    _syncAckPolling(job);

    // Callers reach /active-job via go() or pushReplacement() — by design,
    // because the /job-request "Accept & Start Job" screen must not sit in
    // the back stack once the artisan has committed. That leaves the route
    // stack empty (or pointing at a consumed pre-accept route), so both
    // context.pop() and the OS back gesture fall through. Force back to
    // /trips (My Jobs) so the artisan always lands on their job list —
    // where the active job is still visible — and never back on the
    // "Accept & Start Job" screen.
    void goBackToJobs() => context.go('/trips');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        goBackToJobs();
      },
      child: Scaffold(
        backgroundColor: MyShopColors.surfaceWhite,
        body: Stack(
          children: [
            // ── Full-screen map. Owns its own controller, GPS subscription,
            //    and Directions cache, so a fresh fix doesn't rebuild this
            //    Stack — only the map widget reconciles its markers.
            Positioned.fill(
              child: RepaintBoundary(
                child: _NavigationMap(
                  destination: destination,
                  handle: _mapHandle,
                  metrics: _liveMetrics,
                ),
              ),
            ),

            // ── Top header. Rebuilds on every metrics tick (cheap text
            // only). When the Directions API has surfaced steps for the
            // current leg, the header swaps the Distance/ETA chips for
            // a maneuver row ("Turn left in 250m onto Liberation Rd")
            // so the artisan gets the same turn-by-turn cue the
            // driver-side screen renders. Falls back to chips when no
            // steps are available (fallback straight-line route).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<_LiveMetrics>(
                valueListenable: _liveMetrics,
                builder: (context, metrics, _) {
                  return _NavHeader(
                    clientName: job.clientName ?? 'Client',
                    address: job.addressText ?? 'Destination',
                    liveDistanceMeters: metrics.distanceMeters,
                    liveEtaMinutes: metrics.etaMinutes,
                    progress: metrics.progress,
                    onBack: goBackToJobs,
                    onRecenter: () => _mapHandle.recenter?.call(),
                    onOpenInMaps: () => _launchExternalNavigation(destination),
                  );
                },
              ),
            ),

            // ── Bottom action panel / completion overlay ─────────────────
            // Once the artisan marks complete, the active-work controls
            // stop being useful — swap to a modal-style overlay driven by
            // the backend's status so the UI stays in lockstep with
            // Paystack's webhook (artisan_marked_complete → pending_payment
            // → completed). The overlay auto-dismisses to a success card
            // the moment the job settles, and "Go to Earnings" closes the
            // flow and clears the active-job slot.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _isCompletionPhase(job.status)
                  ? _CompletionOverlay(
                      status: job.status,
                      clientFirstName:
                          (job.clientName ?? 'Client').split(' ').first,
                      isUpdating: state.isUpdating,
                      clientCashAcknowledged: job.isClientCashAcknowledged,
                      startedAt: job.startedAtDateTime,
                      completedAt: job.completedAtDateTime,
                      onGoToEarnings: () {
                        ref.read(activeJobProvider.notifier).clear();
                        context.go('/earnings');
                      },
                      onConfirmCashReceipt: () => ref
                          .read(activeJobProvider.notifier)
                          .confirmCashReceipt(),
                    )
                  : _BottomPanel(
                      job: job,
                      isUpdating: state.isUpdating,
                      onAdvance: () =>
                          ref.read(activeJobProvider.notifier).advance(),
                      onCall: () {},
                      onRequestSupplement: () =>
                          context.push('/supplement-request'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Live header metrics — pushed up from the map widget on each GPS fix.
// ─────────────────────────────────────────────────────────────────────────

class _LiveMetrics {
  const _LiveMetrics({this.distanceMeters, this.etaMinutes, this.progress});

  /// Straight-line distance from current GPS to the destination, in
  /// meters. Null until we get the first fix.
  final double? distanceMeters;

  /// Estimated minutes remaining, derived from the Directions route's
  /// average road speed applied to [distanceMeters].
  final int? etaMinutes;

  /// Live navigation progress for the maneuver banner. Null on the
  /// fallback straight-line route; the banner downgrades gracefully.
  final NavProgress? progress;
}

/// Recenter shim — handed to [_NavigationMap] so it can register a
/// callback the parent header can fire without holding the native
/// controller itself.
class _MapHandle {
  VoidCallback? recenter;
}

// ─────────────────────────────────────────────────────────────────────────
// _NavigationMap — owns the GoogleMap, its controller, the Directions
// route cache, and the GPS subscription. Crucially this widget is the only
// thing that watches `driverLocationStreamProvider`, so a new fix triggers
// a setState INSIDE this widget only — the parent Stack doesn't rebuild,
// the GoogleMap's `markers`/`polylines` Sets keep identity unless they
// truly changed, and the platform-view bridge isn't churned every second.
//
// `myLocationEnabled` is intentionally false: running Core Location in the
// Maps SDK on top of geolocator's existing stream doubles the location
// subsystem and was the proximate cause of the 2 GB memory watermark
// crash on iOS.
// ─────────────────────────────────────────────────────────────────────────

class _NavigationMap extends ConsumerStatefulWidget {
  const _NavigationMap({
    required this.destination,
    required this.handle,
    required this.metrics,
  });

  final LatLng destination;
  final _MapHandle handle;
  final ValueNotifier<_LiveMetrics> metrics;

  @override
  ConsumerState<_NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends ConsumerState<_NavigationMap> {
  GoogleMapController? _mapController;
  DirectionsRoute? _route;
  bool _routeLoading = false;

  /// Origin (artisan GPS) used when the last route was fetched — lets us
  /// skip a refetch if the GPS fix has barely moved.
  LatLng? _lastRouteOrigin;

  /// Rate limit on the Directions API independent of GPS chatter — even
  /// fast movement shouldn't refetch more than once per [_routeRefreshThrottle].
  DateTime? _lastRouteFetchAt;

  /// Most recent GPS fix. Stored in a field rather than via ref.watch so
  /// the GoogleMap only rebuilds when this widget calls setState.
  LatLng? _artisan;

  /// Turn-by-turn nav follow. While true the camera tracks the artisan
  /// on every GPS fix with a 2D top-down rotated-to-heading pose — same
  /// behaviour as Google Maps "Start" mode. Flips to false the moment
  /// the user drags or pinches the map; the recenter button restores it.
  bool _followCamera = true;

  /// Last heading we used for the camera bearing. GPS `heading` is NaN
  /// when stationary and noisy below ~1 m/s; we keep the previous good
  /// value so the camera doesn't spin while the artisan is parked.
  double _lastBearing = 0;

  /// True while we're mid-animation — `onCameraMoveStarted` fires for
  /// our own programmatic moves too, which would otherwise flip
  /// `_followCamera` off and break the next fix.
  bool _programmaticCameraMove = false;

  /// Cached marker + polyline sets. Identity is stable across rebuilds
  /// unless their inputs change, which avoids needless platform-view
  /// reconciliation.
  Set<Marker> _markers = const <Marker>{};
  Set<Polyline> _polylines = const <Polyline>{};

  static const _routeRefreshMeters = 80.0;
  static const _routeRefreshThrottle = Duration(seconds: 30);

  /// Driver/artisan is "off-route" once they're this far from the
  /// nearest point on the route polyline — triggers a forced re-fetch
  /// so the maneuver banner doesn't stale-instruct.
  static const _offRouteThresholdMeters = 65.0;

  /// Top-down 2D nav pose with the camera rotated to match the
  /// artisan's heading. Zoom 17.5 mirrors Google Maps' "Start" mode at
  /// city speeds.
  static const _navZoom = 17.5;
  static const _navTilt = 0.0;

  /// Spoken turn-by-turn coach. Owned per-state so it disposes with
  /// the screen — no orphan TTS sessions surviving navigation away
  /// from the active job.
  final NavVoiceCoach _voice = NavVoiceCoach();

  @override
  void initState() {
    super.initState();
    widget.handle.recenter = _handleRecenter;
    _markers = _buildMarkers();
  }

  @override
  void dispose() {
    if (widget.handle.recenter == _handleRecenter) {
      widget.handle.recenter = null;
    }
    _voice.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _handleRecenter() {
    final artisan = _artisan;
    if (artisan == null) return;
    // Restore nav follow: snap to the artisan with the 2D rotated pose
    // and re-fetch the route so the polyline reflects their current
    // position right away.
    _followCamera = true;
    _animateCameraToArtisan(artisan, _lastBearing);
    _refreshRouteIfNeeded(artisan, force: true);
  }

  /// Animate the camera into nav-mode pose (top-down + rotated +
  /// zoomed). Wrapped in [_programmaticCameraMove] so the
  /// onCameraMoveStarted hook doesn't mistake our own animation for a
  /// user gesture and flip [_followCamera] off mid-flight.
  void _animateCameraToArtisan(LatLng position, double bearing) {
    final controller = _mapController;
    if (controller == null) return;
    _programmaticCameraMove = true;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: position,
          zoom: _navZoom,
          tilt: _navTilt,
          bearing: bearing,
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _programmaticCameraMove = false;
    });
  }

  Future<void> _refreshRouteIfNeeded(
    LatLng origin, {
    bool force = false,
  }) async {
    if (_routeLoading) return;

    if (!force) {
      final last = _lastRouteOrigin;
      if (last != null && _route != null) {
        final drift = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          origin.latitude,
          origin.longitude,
        );
        if (drift < _routeRefreshMeters) return;
      }
      final lastAt = _lastRouteFetchAt;
      if (lastAt != null &&
          DateTime.now().difference(lastAt) < _routeRefreshThrottle) {
        return;
      }
    }

    _routeLoading = true;
    _lastRouteFetchAt = DateTime.now();
    try {
      final route = await ref.read(directionsServiceProvider).fetchRoute(
            origin: origin,
            destination: widget.destination,
          );
      if (!mounted) return;
      setState(() {
        _route = route;
        _lastRouteOrigin = origin;
        _polylines = _buildPolylines();
      });
      // Deliberately NO bounds-fit here — the camera is owned by the
      // nav-follow path in `_onPositionFix`. The earlier fit-on-route-
      // refresh would yank the camera back to a wide two-pin overview
      // and break live navigation; same fix applied to the driver
      // active-ride screen.
      _publishMetrics();
    } finally {
      _routeLoading = false;
    }
  }

  void _onPositionFix(Position pos) {
    if (!mounted) return;
    final next = LatLng(pos.latitude, pos.longitude);
    final prev = _artisan;

    // Cheap dedupe — the geolocator's 5 m distanceFilter already throttles
    // emissions, but guard so we never rebuild for the same fix.
    if (prev != null &&
        prev.latitude == next.latitude &&
        prev.longitude == next.longitude) {
      return;
    }

    // Bearing tracking — same noise-suppression as the driver screen:
    // ignore NaN/slow-speed values so the rotated camera doesn't spin
    // while the artisan is parked.
    final bearing = (pos.heading.isFinite && pos.speed >= 1.0)
        ? pos.heading
        : _lastBearing;
    _lastBearing = bearing;

    setState(() {
      _artisan = next;
      _markers = _buildMarkers();
    });

    if (_followCamera) {
      _animateCameraToArtisan(next, bearing);
    }

    _publishMetrics();
    _refreshRouteIfNeeded(next);
  }

  void _publishMetrics() {
    final artisan = _artisan;
    if (artisan == null) {
      widget.metrics.value = const _LiveMetrics();
      return;
    }
    final distance = _haversineMeters(artisan, widget.destination);
    final route = _route;
    final progress = route != null
        ? NavGuidance.progressFor(driver: artisan, route: route)
        : null;
    widget.metrics.value = _LiveMetrics(
      distanceMeters: distance,
      etaMinutes: _liveEtaMinutes(distance, route),
      progress: progress,
    );

    if (progress != null && progress.currentStep != null) {
      _voice.announce(progress);
    }

    final offBy = progress?.offRouteMeters;
    if (offBy != null && offBy > _offRouteThresholdMeters && !_routeLoading) {
      _voice.reset();
      _refreshRouteIfNeeded(artisan, force: true);
    }
  }

  Set<Marker> _buildMarkers() {
    final artisan = _artisan;
    return <Marker>{
      Marker(
        markerId: const MarkerId('client'),
        position: widget.destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      if (artisan != null)
        Marker(
          markerId: const MarkerId('artisan'),
          position: artisan,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };
  }

  Set<Polyline> _buildPolylines() {
    final route = _route;
    if (route == null || route.polyline.length < 2) {
      return const <Polyline>{};
    }
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: route.polyline,
        color: MyShopColors.primaryGold,
        width: 5,
        patterns: route.isFallback
            ? [PatternItem.dash(20), PatternItem.gap(12)]
            : const [],
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  // Removed `_fitCamera` (bounds-fit of [artisan, destination]). It
  // ran on map creation and on every route refresh, and the animation
  // fired `onCameraMoveStarted` without the programmatic guard — which
  // silently flipped `_followCamera` off (once we added it) and
  // stranded the camera in a static two-pin overview. Nav mode now
  // owns the camera from the very first GPS fix.

  @override
  Widget build(BuildContext context) {
    // Listen, don't watch — we want to react to fixes inside _onPositionFix
    // without rebuilding via Riverpod. setState there decides whether the
    // GoogleMap actually needs to reconcile.
    ref.listen<AsyncValue<Position>>(driverLocationStreamProvider,
        (prev, next) {
      next.whenData(_onPositionFix);
    });

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _artisan ?? widget.destination,
        zoom: 14,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        final artisan = _artisan;
        if (artisan != null) {
          _animateCameraToArtisan(artisan, _lastBearing);
        }
      },
      // User drag/pinch → pause follow so we don't fight their gesture.
      // The recenter button on the header restores it. Programmatic
      // moves carry [_programmaticCameraMove] so they don't trip the
      // pause path themselves.
      onCameraMoveStarted: () {
        if (_programmaticCameraMove) return;
        if (_followCamera) {
          setState(() => _followCamera = false);
        }
      },
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 160,
        bottom: 260,
      ),
      markers: _markers,
      polylines: _polylines,
    );
  }

  /// Great-circle distance in meters. Used for the live header distance so
  /// it ticks down on every GPS fix without hammering the Directions API.
  static double _haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 + s2 * s2 * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  /// Estimated minutes to destination from the last Directions response's
  /// average road speed. Falls back to a 30 km/h assumption when we don't
  /// have a full Directions route yet (first GPS fix, API error, etc.).
  static int? _liveEtaMinutes(
    double? meters,
    DirectionsRoute? route,
  ) {
    if (meters == null) return null;
    double? mps;
    if (route != null &&
        !route.isFallback &&
        route.durationSeconds > 0 &&
        route.distanceMeters > 0) {
      mps = route.distanceMeters / route.durationSeconds;
    }
    // 30 km/h ≈ 8.33 m/s — a conservative Kumasi-street default.
    mps ??= 8.333;
    return (meters / mps / 60).round();
  }
}

/// Sanity check on a destination [LatLng]. The backend has been seen to
/// hand out jobs with `(0, 0)` when geocoding fails — mounting a GoogleMap
/// with that as the destination forces the SDK to fit a multi-thousand-km
/// camera bound across the ocean, which blows past iOS's jetsam watermark.
bool _isValidLatLng(LatLng p) {
  if (p.latitude.isNaN || p.longitude.isNaN) return false;
  if (p.latitude.abs() < 0.0001 && p.longitude.abs() < 0.0001) return false;
  if (p.latitude.abs() > 90 || p.longitude.abs() > 180) return false;
  return true;
}

// ─────────────────────────────────────────────────────────────────────────
// Empty state — job has no usable coordinates. Surfaces what's wrong
// rather than mounting a map that would crash the process.
// ─────────────────────────────────────────────────────────────────────────

class _NoJobLocation extends StatelessWidget {
  const _NoJobLocation({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: MyShopColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_off_outlined,
                  size: 56,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(height: MyShopSpacing.md),
                Text(
                  'Job location missing',
                  style: MyShopTypography.h2.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                Text(
                  job.addressText ??
                      "This job doesn't have GPS coordinates yet, so we "
                          "can't open the map. Try again in a moment, or "
                          'contact the client for directions.',
                  textAlign: TextAlign.center,
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.textSecondary,
                  ),
                ),
                const SizedBox(height: MyShopSpacing.lg),
                ElevatedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Empty state — the artisan landed here without an active job in state.
// Usually only happens during dev; the banner action seeds the slot.
// ─────────────────────────────────────────────────────────────────────────

class _NoActiveJob extends StatelessWidget {
  const _NoActiveJob();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.inbox_outlined,
                  size: 56,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(height: MyShopSpacing.md),
                Text(
                  'No active job',
                  style: MyShopTypography.h2.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                Text(
                  "You'll land here once you accept a bid and start heading "
                  'to the client.',
                  textAlign: TextAlign.center,
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.textSecondary,
                  ),
                ),
                const SizedBox(height: MyShopSpacing.lg),
                ElevatedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Top nav header — back button + client info card + overflow actions.
// ─────────────────────────────────────────────────────────────────────────

class _NavHeader extends StatelessWidget {
  const _NavHeader({
    required this.clientName,
    required this.address,
    required this.liveDistanceMeters,
    required this.liveEtaMinutes,
    required this.progress,
    required this.onBack,
    required this.onRecenter,
    required this.onOpenInMaps,
  });

  final String clientName;
  final String address;

  /// Straight-line distance from current GPS to the destination, in
  /// meters. Recomputed on every GPS fix so the label ticks down live.
  final double? liveDistanceMeters;

  /// Estimated minutes remaining, derived from the Directions route's
  /// average road speed applied to [liveDistanceMeters]. Null when we
  /// don't yet have a GPS fix.
  final int? liveEtaMinutes;

  /// Live navigation progress — when non-null and carrying a
  /// [NavProgress.currentStep], the header swaps the chip row for a
  /// maneuver instruction.
  final NavProgress? progress;
  final VoidCallback onBack;
  final VoidCallback onRecenter;
  final VoidCallback onOpenInMaps;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final distanceLabel = liveDistanceMeters != null
        ? (liveDistanceMeters! < 1000
            ? '${liveDistanceMeters!.round()} m'
            : '${(liveDistanceMeters! / 1000).toStringAsFixed(1)} km')
        : '— km';
    final etaLabel = (liveEtaMinutes != null && liveEtaMinutes! > 0)
        ? '${liveEtaMinutes!} min'
        : (liveEtaMinutes == 0 ? 'Arriving' : '—');
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        topPad + MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CircleIconButton(icon: Icons.arrow_back, onTap: onBack),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: MyShopTypography.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _CircleIconButton(
                icon: Icons.my_location,
                onTap: onRecenter,
              ),
              const SizedBox(width: MyShopSpacing.xs),
              _CircleIconButton(
                icon: Icons.navigation_outlined,
                onTap: onOpenInMaps,
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          if (progress?.currentStep != null)
            _ManeuverRow(progress: progress!, etaLabel: etaLabel)
          else
            Row(
              children: [
                _MetricChip(
                  icon: Icons.route_outlined,
                  label: 'Distance',
                  value: distanceLabel,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                _MetricChip(
                  icon: Icons.access_time,
                  label: 'ETA',
                  value: etaLabel,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Compact maneuver row shown inside the artisan nav header when the
/// Directions API has surfaced steps for the current leg. Pairs a turn
/// arrow + distance with the full instruction and the route ETA on the
/// right. Visually shorter than the driver-side full [ManeuverBanner]
/// because the artisan header already carries the client-info row above.
class _ManeuverRow extends StatelessWidget {
  const _ManeuverRow({required this.progress, required this.etaLabel});

  final NavProgress progress;
  final String etaLabel;

  @override
  Widget build(BuildContext context) {
    final step = progress.currentStep!;
    final dist = progress.distanceToManeuverMeters;
    final distanceLabel = dist < 1000
        ? '${(dist / 10).round() * 10} m'
        : '${(dist / 1000).toStringAsFixed(1)} km';
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: MyShopColors.darkSlate,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_maneuverIcon(step.maneuver),
              size: 26, color: Colors.white),
        ),
        const SizedBox(width: MyShopSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(distanceLabel,
                  style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textPrimary,
                      height: 1.1)),
              const SizedBox(height: 2),
              Text(
                step.instruction.isNotEmpty ? step.instruction : 'Continue',
                style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textSecondary,
                    height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(width: 1, height: 32, color: MyShopColors.divider),
        const SizedBox(width: MyShopSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('ETA',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.primaryGold,
                    letterSpacing: 0.4)),
            const SizedBox(height: 2),
            Text(etaLabel,
                style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textPrimary)),
          ],
        ),
      ],
    );
  }

  static IconData _maneuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-right':
        return Icons.turn_right;
      case 'turn-sharp-left':
      case 'turn-slight-left':
        return Icons.turn_sharp_left;
      case 'turn-sharp-right':
      case 'turn-slight-right':
        return Icons.turn_sharp_right;
      case 'uturn-left':
      case 'uturn-right':
        return Icons.u_turn_left;
      case 'ramp-left':
      case 'fork-left':
        return Icons.ramp_left;
      case 'ramp-right':
      case 'fork-right':
        return Icons.ramp_right;
      case 'merge':
        return Icons.merge;
      case 'roundabout-left':
      case 'roundabout-right':
        return Icons.roundabout_right;
      default:
        return Icons.straight;
    }
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: MyShopColors.textPrimary),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md,
          vertical: MyShopSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.offWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: MyShopColors.primaryGold),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    value,
                    style: MyShopTypography.h3.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Bottom panel — timeline + primary action + message/call.
// ─────────────────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.job,
    required this.isUpdating,
    required this.onAdvance,
    required this.onCall,
    required this.onRequestSupplement,
  });

  final Job job;
  final bool isUpdating;
  final VoidCallback onAdvance;
  final VoidCallback onCall;

  /// Push the supplement-request screen. Only surfaces while the backend
  /// allows a supplement — before `inProgress` per the marketplace
  /// controller's "before work starts" rule.
  final VoidCallback onRequestSupplement;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md + bottomPad,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _JobTimeline(current: job.status),
          // Show the live "Time on job" pill from the moment the artisan
          // taps "Start job" and through any later phases. Hidden until
          // `startedAt` is populated (either by the local stamp in the
          // notifier or by the backend echoing the value back).
          if (job.startedAtDateTime != null) ...[
            const SizedBox(height: MyShopSpacing.md),
            JobElapsedTime(
              startedAt: job.startedAtDateTime,
              endedAt: job.completedAtDateTime,
              label: job.completedAtDateTime != null
                  ? 'Final duration'
                  : 'Time on job',
            ),
          ],
          const SizedBox(height: MyShopSpacing.md),
          _PrimaryActionButton(
            status: job.status,
            isLoading: isUpdating,
            onTap: onAdvance,
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ChatEntryButton(
                  bookingType: ChatBookingType.artisanJob,
                  bookingId: job.id,
                  label: 'Message',
                  peerName: job.clientName ?? 'Client',
                  peerStatus: 'On the job',
                  background: MyShopColors.surfaceWhite,
                  foreground: MyShopColors.textPrimary,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: _SecondaryButton(
                  icon: Icons.phone_outlined,
                  label: 'Call',
                  onTap: onCall,
                ),
              ),
            ],
          ),
          if (_supplementAllowed) ...[
            const SizedBox(height: MyShopSpacing.sm),
            TextButton.icon(
              onPressed: onRequestSupplement,
              icon: const Icon(Icons.add_card_outlined, size: 18),
              label: const Text(
                'Request material supplement',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: MyShopColors.primaryGoldDark,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Surface the supplement entry point ONLY while the backend will
  /// accept a `POST /jobs/:id/supplement` call — i.e. before the artisan
  /// starts work. Hiding it afterwards keeps the UI honest with the
  /// "before work starts" rule on the controller, and prevents the
  /// artisan racking up disputes by trying to add charges late.
  bool get _supplementAllowed {
    switch (job.status) {
      case JobStatus.confirmed:
      case JobStatus.artisanEnRoute:
      case JobStatus.arrived:
        return true;
      default:
        return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Timeline — shows the en_route → arrived → in_progress → complete phases
// and highlights the one that matches the current [JobStatus].
// ─────────────────────────────────────────────────────────────────────────

class _JobTimeline extends StatelessWidget {
  const _JobTimeline({required this.current});

  final JobStatus current;

  static const _phases = <_TimelinePhase>[
    _TimelinePhase(
      status: JobStatus.artisanEnRoute,
      label: 'En route',
      icon: Icons.navigation_outlined,
    ),
    _TimelinePhase(
      status: JobStatus.arrived,
      label: 'Arrived',
      icon: Icons.location_on_outlined,
    ),
    _TimelinePhase(
      status: JobStatus.inProgress,
      label: 'In progress',
      icon: Icons.handyman_outlined,
    ),
    _TimelinePhase(
      status: JobStatus.artisanMarkedComplete,
      label: 'Complete',
      icon: Icons.check_circle_outline,
    ),
  ];

  int get _currentIndex {
    for (int i = 0; i < _phases.length; i++) {
      if (_phases[i].status == current) return i;
    }
    // Confirmed (just accepted, en_route not yet acked) → highlight "En route"
    if (current == JobStatus.confirmed) return 0;
    // Fully completed — keep the last pill active.
    if (current == JobStatus.completed) return _phases.length - 1;
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final active = _currentIndex;
    return Row(
      children: [
        for (int i = 0; i < _phases.length; i++) ...[
          Expanded(
            child: _PhaseDot(
              phase: _phases[i],
              state: i < active
                  ? _PhaseState.done
                  : i == active
                      ? _PhaseState.active
                      : _PhaseState.upcoming,
            ),
          ),
          if (i < _phases.length - 1)
            Container(
              width: 12,
              height: 2,
              color:
                  i < active ? MyShopColors.primaryGold : MyShopColors.divider,
            ),
        ],
      ],
    );
  }
}

enum _PhaseState { upcoming, active, done }

class _TimelinePhase {
  const _TimelinePhase({
    required this.status,
    required this.label,
    required this.icon,
  });

  final JobStatus status;
  final String label;
  final IconData icon;
}

class _PhaseDot extends StatelessWidget {
  const _PhaseDot({required this.phase, required this.state});

  final _TimelinePhase phase;
  final _PhaseState state;

  Color get _bg => switch (state) {
        _PhaseState.done => MyShopColors.primaryGold,
        _PhaseState.active => MyShopColors.primaryGold,
        _PhaseState.upcoming => MyShopColors.surfaceGrey,
      };

  Color get _fg => switch (state) {
        _PhaseState.done => MyShopColors.textOnPrimary,
        _PhaseState.active => MyShopColors.textOnPrimary,
        _PhaseState.upcoming => MyShopColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _bg,
            shape: BoxShape.circle,
            border: state == _PhaseState.active
                ? Border.all(color: MyShopColors.primaryGold, width: 3)
                : null,
          ),
          child: Icon(
            state == _PhaseState.done ? Icons.check : phase.icon,
            size: 16,
            color: _fg,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          phase.label,
          textAlign: TextAlign.center,
          style: MyShopTypography.caption.copyWith(
            fontWeight:
                state == _PhaseState.active ? FontWeight.w900 : FontWeight.w600,
            color: state == _PhaseState.upcoming
                ? MyShopColors.textSecondary
                : MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Primary advance-status button — label + colour follow [JobStatus].
// ─────────────────────────────────────────────────────────────────────────

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.status,
    required this.isLoading,
    required this.onTap,
  });

  final JobStatus status;
  final bool isLoading;
  final VoidCallback onTap;

  (String, IconData) get _content {
    switch (status) {
      case JobStatus.confirmed:
      case JobStatus.artisanEnRoute:
        return ("I've arrived", Icons.location_on_outlined);
      case JobStatus.arrived:
        return ('Start job', Icons.play_circle_outline);
      case JobStatus.inProgress:
        return ('Mark complete', Icons.check_circle_outline);
      case JobStatus.artisanMarkedComplete:
        return ('Awaiting client', Icons.hourglass_top);
      case JobStatus.pendingPayment:
        return ('Awaiting payment', Icons.payments_outlined);
      case JobStatus.completed:
      case JobStatus.cancelled:
      case JobStatus.pendingAdmin:
      case JobStatus.adminAssigned:
      case JobStatus.open:
      case JobStatus.queued:
        return ('Awaiting client', Icons.hourglass_top);
    }
  }

  bool get _isTerminal =>
      status == JobStatus.artisanMarkedComplete ||
      status == JobStatus.pendingPayment ||
      status == JobStatus.completed ||
      status == JobStatus.cancelled;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _content;
    final disabled = isLoading || _isTerminal;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: disabled
              ? MyShopColors.darkSlate.withValues(alpha: 0.7)
              : MyShopColors.darkSlate,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation(MyShopColors.textOnDarkSlate),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: MyShopColors.textOnDarkSlate),
                  const SizedBox(width: MyShopSpacing.sm),
                  Text(
                    label,
                    style: MyShopTypography.button.copyWith(
                      color: MyShopColors.textOnDarkSlate,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: MyShopColors.textPrimary),
            const SizedBox(width: MyShopSpacing.sm),
            Text(
              label,
              style: MyShopTypography.button.copyWith(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Completion overlay
//
// Mounted once the artisan has marked the job complete. Its content is
// driven entirely by the backend status so the socket
// `job:status:changed` event (which silently reloads the jobs list and
// reconciles `activeJobProvider.job.status`) walks us through:
//
//   artisan_marked_complete → "Waiting for client"
//   pending_payment         → "Client is paying…"
//   completed               → success card + "Go to Earnings" CTA
//
// Intentionally NOT a Navigator-pushed modal — keeping it in the widget
// tree means the status change flips the card in place, so there's no
// race with dismissing a modal bottom sheet mid-socket-event.
// ─────────────────────────────────────────────────────────────────────────

bool _isCompletionPhase(JobStatus status) =>
    status == JobStatus.artisanMarkedComplete ||
    status == JobStatus.pendingPayment ||
    status == JobStatus.completed;

class _CompletionOverlay extends StatelessWidget {
  const _CompletionOverlay({
    required this.status,
    required this.clientFirstName,
    required this.isUpdating,
    required this.clientCashAcknowledged,
    required this.startedAt,
    required this.completedAt,
    required this.onGoToEarnings,
    required this.onConfirmCashReceipt,
  });

  final JobStatus status;
  final String clientFirstName;

  /// When work began. Drives the frozen "Final duration" pill at the top
  /// of the overlay — null hides the pill entirely (e.g. legacy jobs
  /// that finished before the timestamp shipped).
  final DateTime? startedAt;

  /// When the artisan flipped the job to `artisan_marked_complete`.
  /// Pairs with [startedAt] to render the final on-the-job duration.
  final DateTime? completedAt;

  /// True while the PATCH /confirm for cash receipt is in flight — dims
  /// the Yes/No row and swaps the "Yes" label for a spinner.
  final bool isUpdating;

  /// True once the client has tapped "Proceed to Payment" and picked Cash
  /// (set via `job:client_payment_acknowledged` socket event or a refetch).
  /// Until this flips true, the artisan-confirm-cash endpoint will 409
  /// with `CLIENT_PAYMENT_NOT_ACKNOWLEDGED`, so we keep the "Yes, I
  /// received payment" CTA disabled and show a "Waiting for client" hint.
  final bool clientCashAcknowledged;
  final VoidCallback onGoToEarnings;
  final VoidCallback onConfirmCashReceipt;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final isCompleted = status == JobStatus.completed;
    // Two distinct waiting states:
    //   - awaitingCashReceipt (artisan_marked_complete): client either
    //     hasn't picked yet OR picked Cash, which never hits
    //     /payments/initiate. The artisan is the source of truth — show
    //     the Yes / Not yet CTAs so they can flip the job to completed
    //     via POST /jobs/:id/artisan-confirm-cash.
    //   - paystackInFlight (pending_payment): client picked an in-app
    //     method, charge is queued, Paystack webhook will settle it
    //     automatically. NO buttons — tapping anything here would 403,
    //     and any artisan-side action would be wrong: only the webhook
    //     can authoritatively say the charge cleared.
    final awaitingCashReceipt = status == JobStatus.artisanMarkedComplete;
    final paystackInFlight = status == JobStatus.pendingPayment;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          MyShopSpacing.lg,
          MyShopSpacing.lg,
          MyShopSpacing.lg,
          bottomPad + MyShopSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            _CompletionIcon(status: status),
            const SizedBox(height: MyShopSpacing.md),

            // Surface the on-the-job duration on the completion overlay
            // so the artisan sees how long they spent before they walk
            // away from the screen. Frozen (no live ticking) once the
            // job is in any completion phase — `completedAt` is set.
            if (startedAt != null) ...[
              JobElapsedTime(
                startedAt: startedAt,
                endedAt: completedAt ?? DateTime.now(),
                label: 'Final duration',
              ),
              const SizedBox(height: MyShopSpacing.md),
            ],

            Text(
              _titleFor(status, clientCashAcknowledged),
              textAlign: TextAlign.center,
              style: MyShopTypography.h2.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              _subtitleFor(status, clientFirstName, clientCashAcknowledged),
              textAlign: TextAlign.center,
              style: MyShopTypography.body1.copyWith(
                color: MyShopColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            if (isCompleted)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onGoToEarnings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.darkSlate,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: MyShopColors.textOnDarkSlate,
                          size: 20,
                        ),
                        const SizedBox(width: MyShopSpacing.sm),
                        Text(
                          'Go to Earnings',
                          style: MyShopTypography.button.copyWith(
                            color: MyShopColors.textOnDarkSlate,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (awaitingCashReceipt)
              // Job is `artisan_marked_complete` and there's no pending
              // Paystack charge — either the client picked Cash or hasn't
              // picked yet. The artisan is the source of truth: tapping
              // "Yes" calls the artisan-confirms-cash endpoint and flips
              // the job to completed. "Not yet" closes the overlay and
              // leaves the job as-is.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isUpdating ? null : onGoToEarnings,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: MyShopColors.divider),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Not yet',
                        style: MyShopTypography.button.copyWith(
                          color: MyShopColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: MyShopSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (isUpdating || !clientCashAcknowledged)
                          ? null
                          : onConfirmCashReceipt,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyShopColors.success,
                        disabledBackgroundColor:
                            MyShopColors.success.withValues(alpha: 0.4),
                        elevation: 0,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isUpdating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(
                                  MyShopColors.surfaceWhite,
                                ),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    clientCashAcknowledged
                                        ? Icons.check_circle_outline
                                        : Icons.hourglass_empty_rounded,
                                    color: MyShopColors.surfaceWhite,
                                    size: 20,
                                  ),
                                  const SizedBox(width: MyShopSpacing.sm),
                                  Text(
                                    clientCashAcknowledged
                                        ? 'Yes, I received payment'
                                        : 'Waiting for client',
                                    style: MyShopTypography.button.copyWith(
                                      color: MyShopColors.surfaceWhite,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              )
            else if (paystackInFlight)
              // Paystack charge in flight — webhook is the only thing that
              // can authoritatively settle this. Show a passive progress
              // bar so the artisan sees the UI is live; do NOT show any
              // CTAs because the artisan has nothing to do (and any
              // /confirm call would 403 anyway, since the client owns
              // that endpoint).
              const LinearProgressIndicator(
                minHeight: 3,
                color: MyShopColors.primaryGold,
                backgroundColor: MyShopColors.surfaceGrey,
              )
            else
              // Other terminal-ish states — fall back to the same passive
              // progress bar.
              const LinearProgressIndicator(
                minHeight: 3,
                color: MyShopColors.primaryGold,
                backgroundColor: MyShopColors.surfaceGrey,
              ),
          ],
        ),
      ),
    );
  }

  static String _titleFor(JobStatus status, bool clientCashAcknowledged) {
    switch (status) {
      case JobStatus.artisanMarkedComplete:
        return clientCashAcknowledged
            ? 'Did you receive cash?'
            : 'Waiting for client to confirm payment';
      case JobStatus.pendingPayment:
        return 'Client is paying';
      case JobStatus.completed:
        return 'Job complete!';
      default:
        return 'Waiting for client confirmation';
    }
  }

  static String _subtitleFor(
    JobStatus status,
    String clientFirstName,
    bool clientCashAcknowledged,
  ) {
    switch (status) {
      case JobStatus.artisanMarkedComplete:
        if (!clientCashAcknowledged) {
          return "$clientFirstName hasn't picked a payment method yet. "
              "Once they tap 'Proceed to Payment' and choose Cash, you'll "
              'be able to confirm receipt here.';
        }
        return "$clientFirstName has chosen Cash. If they've handed you "
            'the money, tap "Yes, I received payment" to settle the job.';
      case JobStatus.pendingPayment:
        return "$clientFirstName's Paystack charge is settling. Hang "
            'tight — your earnings release automatically once the bank '
            "confirms (usually a few seconds). You don't need to do "
            'anything here.';
      case JobStatus.completed:
        return 'Payment has been released to your wallet. Check your '
            'earnings to see the breakdown.';
      default:
        return "You've marked the job done. $clientFirstName needs to "
            'review and pay before your earnings release.';
    }
  }
}

class _CompletionIcon extends StatelessWidget {
  const _CompletionIcon({required this.status});

  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      JobStatus.completed => (Icons.check_circle_rounded, MyShopColors.success),
      JobStatus.pendingPayment => (
          Icons.payments_outlined,
          MyShopColors.primaryGold,
        ),
      _ => (Icons.hourglass_top_rounded, MyShopColors.primaryGold),
    };
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 36, color: color),
    );
  }
}
