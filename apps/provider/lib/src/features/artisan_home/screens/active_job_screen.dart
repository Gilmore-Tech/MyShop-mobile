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

import '../../../core/services/directions_service.dart';
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
    _liveMetrics.dispose();
    super.dispose();
  }

  Future<void> _maybeShowRateClientSheet() async {
    if (_rateSheetShown || !mounted) return;
    final job = ref.read(activeJobProvider).job;
    if (job == null || job.id.isEmpty) return;
    _rateSheetShown = true;
    final firstName = (job.clientName ?? 'Client').trim().split(' ').first;
    await showRateClientSheet(
      context,
      jobId: job.id,
      clientFirstName: firstName.isEmpty ? 'Client' : firstName,
    );
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
    });

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

            // ── Top header. Rebuilds on every metrics tick (cheap text only).
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
                      clientFirstName: (job.clientName ?? 'Client')
                          .split(' ')
                          .first,
                      isUpdating: state.isUpdating,
                      clientCashAcknowledged: job.isClientCashAcknowledged,
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
                      onMessage: () => context.push('/chat'),
                      onCall: () {},
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
  const _LiveMetrics({this.distanceMeters, this.etaMinutes});

  /// Straight-line distance from current GPS to the destination, in
  /// meters. Null until we get the first fix.
  final double? distanceMeters;

  /// Estimated minutes remaining, derived from the Directions route's
  /// average road speed applied to [distanceMeters].
  final int? etaMinutes;
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
  bool _hasFittedCamera = false;

  /// Origin (artisan GPS) used when the last route was fetched — lets us
  /// skip a refetch if the GPS fix has barely moved.
  LatLng? _lastRouteOrigin;

  /// Rate limit on the Directions API independent of GPS chatter — even
  /// fast movement shouldn't refetch more than once per [_routeRefreshThrottle].
  DateTime? _lastRouteFetchAt;

  /// Most recent GPS fix. Stored in a field rather than via ref.watch so
  /// the GoogleMap only rebuilds when this widget calls setState.
  LatLng? _artisan;

  /// Cached marker + polyline sets. Identity is stable across rebuilds
  /// unless their inputs change, which avoids needless platform-view
  /// reconciliation.
  Set<Marker> _markers = const <Marker>{};
  Set<Polyline> _polylines = const <Polyline>{};

  static const _routeRefreshMeters = 80.0;
  static const _routeRefreshThrottle = Duration(seconds: 30);

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
    _mapController?.dispose();
    super.dispose();
  }

  void _handleRecenter() {
    final artisan = _artisan;
    if (artisan == null) return;
    _hasFittedCamera = false;
    _fitCamera(origin: artisan, route: _route);
    // Force a fresh route fetch on explicit recenter — bypasses throttles
    // so the user sees an up-to-date polyline immediately.
    _refreshRouteIfNeeded(artisan, force: true);
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
      _fitCamera(origin: origin, route: route);
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

    setState(() {
      _artisan = next;
      _markers = _buildMarkers();
    });
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
    widget.metrics.value = _LiveMetrics(
      distanceMeters: distance,
      etaMinutes: _liveEtaMinutes(distance, _route),
    );
  }

  Set<Marker> _buildMarkers() {
    final artisan = _artisan;
    return <Marker>{
      Marker(
        markerId: const MarkerId('client'),
        position: widget.destination,
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
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

  void _fitCamera({required LatLng origin, required DirectionsRoute? route}) {
    final controller = _mapController;
    if (controller == null) return;
    if (_hasFittedCamera && route == null) return;

    // If the artisan is absurdly far from the destination (bad GPS, bad
    // job coords), don't fit a continent-wide bound — that pre-fetches
    // tiles across the whole region and trips iOS's memory watermark.
    // Service jobs are local; cap at 100 km and just zoom to the artisan
    // when they're further out than that.
    final straightLineMeters = _haversineMeters(origin, widget.destination);
    if (straightLineMeters > 100000) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(origin, 14));
      _hasFittedCamera = true;
      return;
    }

    final points = (route != null && route.polyline.isNotEmpty)
        ? route.polyline
        : <LatLng>[origin, widget.destination];
    double south = points.first.latitude;
    double north = points.first.latitude;
    double west = points.first.longitude;
    double east = points.first.longitude;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        80,
      ),
    );
    _hasFittedCamera = true;
  }

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
          _fitCamera(origin: artisan, route: _route);
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
    required this.onMessage,
    required this.onCall,
  });

  final Job job;
  final bool isUpdating;
  final VoidCallback onAdvance;
  final VoidCallback onMessage;
  final VoidCallback onCall;

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
                child: _SecondaryButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message',
                  onTap: onMessage,
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
        ],
      ),
    );
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
              color: i < active
                  ? MyShopColors.primaryGold
                  : MyShopColors.divider,
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
            fontWeight: state == _PhaseState.active
                ? FontWeight.w900
                : FontWeight.w600,
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
    required this.onGoToEarnings,
    required this.onConfirmCashReceipt,
  });

  final JobStatus status;
  final String clientFirstName;

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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      onPressed:
                          (isUpdating || !clientCashAcknowledged)
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
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
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
