import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:go_router/go_router.dart';

import '../../../core/providers/chat_controller_provider.dart';
import '../../../core/services/directions_service.dart';
import '../../../core/services/nav_guidance.dart';
import '../../../core/widgets/maneuver_banner.dart';
import '../../../core/widgets/nav_arrow_icon.dart';
import '../data/external_nav_service.dart';
import '../providers/driver_location_provider.dart';
import '../providers/ride_request_provider.dart';

/// Active ride screen — drives the four states from accepting a request all
/// the way through to ride completion.
///
/// Figma: nodes 195:11007 (en-route to pickup), 208:11210, 208:11599
/// PRD Reference: PRD 5.2
///
/// State machine:
///   - accepted / driverEnRoute   → full map + navigation header.
///       After ~6 seconds (proximity simulator) the bottom panel slides up
///       offering "ARRIVED AT DESTINATION".
///   - arrived                    → bottom panel stays up; primary action
///       becomes "START TRIP".
///   - inProgress                 → primary action becomes "END TRIP".
///   - completed                  → screen closes.
class ActiveRideScreen extends ConsumerStatefulWidget {
  const ActiveRideScreen({super.key});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// Live distance/ETA pushed up from [_NavigationMap] on each GPS fix.
  /// The header reads it via [ValueListenableBuilder] so the text ticks
  /// down without forcing the GoogleMap to rebuild.
  final ValueNotifier<_LiveMetrics> _liveMetrics =
      ValueNotifier<_LiveMetrics>(const _LiveMetrics());

  /// Lets the recenter button ask the map to refit without holding the
  /// GoogleMapController itself — keeps native resources scoped to the map
  /// widget.
  final _MapHandle _mapHandle = _MapHandle();

  /// Time before the bottom panel auto-presents itself, simulating the
  /// driver getting close to the pickup pin.
  static const _proximityDelay = Duration(seconds: 6);
  static const _previewSize = 0.55;

  /// Smallest fraction of the screen the passenger panel can occupy. Keeps
  /// a peek tab visible so the driver can always grab the panel back even
  /// after collapsing it — without this they could drag it fully off-screen
  /// and have no way to bring it back without re-accepting a ride.
  static const _peekSize = 0.12;

  Timer? _proximityTimer;

  @override
  void initState() {
    super.initState();
    _proximityTimer = Timer(_proximityDelay, () {
      if (!mounted) return;
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          _previewSize,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
    // Note: `accepted → driver_en_route` is fired directly from
    // `ActiveRideNotifier.acceptRide` so it lands the moment the socket
    // ack returns, regardless of when this screen mounts. The backend's
    // stage-timeout service auto-cancels rides stuck in `accepted` after
    // ~2 minutes, so we can't risk the transition being delayed by widget
    // lifecycle quirks.
  }

  /// Manual launch from the Navigate button. Routes to pickup before the
  /// trip starts and dropoff after. The in-app map handles turn-by-turn
  /// natively (camera follows driver, tilts, rotates) so external nav is
  /// purely an opt-in for drivers who prefer Google Maps' voice guidance.
  Future<void> _onNavigatePressed(Ride ride) async {
    final isPostStart = ride.status == RideStatus.inProgress;
    await externalNavService.openDrivingNav(
      lat: isPostStart ? ride.dropoffLat : ride.pickupLat,
      lng: isPostStart ? ride.dropoffLng : ride.pickupLng,
      label: isPostStart ? ride.dropoffAddress : ride.pickupAddress,
    );
  }

  @override
  void dispose() {
    _proximityTimer?.cancel();
    _sheetController.dispose();
    _liveMetrics.dispose();
    super.dispose();
  }

  Future<void> _handlePrimaryAction(Ride ride) async {
    final notifier = ref.read(activeRideProvider.notifier);
    final ok = switch (ride.status) {
      RideStatus.accepted ||
      RideStatus.driverEnRoute =>
        await notifier.markArrived(),
      RideStatus.arrived => await notifier.startTrip(),
      RideStatus.inProgress => await notifier.completeTrip(),
      _ => false,
    };
    if (!mounted) return;
    if (!ok) {
      final message = ref.read(activeRideProvider).errorMessage ??
          "Couldn't update the ride";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    // The activeRideProvider listener below handles navigation when the
    // ride hits a terminal state (completed → trip summary, cancelled →
    // back to home). Don't pop from here — that double-pop was leaving
    // the navigator on a black screen below the home shell.
  }

  /// Bottom sheet with the "off the happy path" actions — currently just
  /// "Cancel ride", which is the only reliable way out when the backend's
  /// status PATCH is failing (e.g. Prisma errors during `complete`) and
  /// the driver would otherwise be stuck on this screen forever.
  Future<void> _showOverflowMenu(Ride ride) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MyShopColors.surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            ListTile(
              leading:
                  const Icon(Icons.cancel_outlined, color: MyShopColors.error),
              title: const Text('Cancel ride',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.error,
                  )),
              subtitle: const Text(
                  "Notify the rider and free yourself for the next trip."),
              onTap: () => Navigator.of(sheetCtx).pop('cancel'),
            ),
            const SizedBox(height: MyShopSpacing.sm),
          ],
        ),
      ),
    );
    if (action != 'cancel' || !mounted) return;
    await _confirmAndCancel(ride);
  }

  Future<void> _confirmAndCancel(Ride ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cancel this ride?'),
        content: const Text(
          'The rider will be notified. A cancellation fee may be deducted '
          'from your next payout, and frequent cancellations can suspend '
          'your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final outcome = await ref.read(activeRideProvider.notifier).cancelRide();
    if (!mounted) return;

    // Surface the outcome before popping. Suspension takes priority — the
    // driver must understand why they can no longer receive requests.
    if (outcome.driverSuspended) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Account suspended'),
          content: const Text(
            'You have been suspended from receiving new ride requests due '
            'to frequent cancellations in the last 30 days. Please contact '
            'support to restore your account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else if (outcome.hasFee) {
      final fee = (outcome.feePesewas / 100).toStringAsFixed(2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ride cancelled. Fee: GHS $fee')),
      );
    }
    if (!mounted) return;
    // Active ride state is now cleared. Route via GoRouter so the
    // matchList stays consistent — `Navigator.pop` would clash with the
    // ride:state listener above (which already navigates on the cancelled
    // snapshot) and trip the "no pages left to show" assertion.
    context.go('/home');
  }

  /// Where the driver is currently navigating to. Pickup until they have
  /// the passenger in the car; drop-off after the trip starts.
  LatLng _routingTarget(Ride ride) {
    return switch (ride.status) {
      RideStatus.inProgress => LatLng(ride.dropoffLat, ride.dropoffLng),
      _ => LatLng(ride.pickupLat, ride.pickupLng),
    };
  }

  String _targetLabel(RideStatus status) {
    return switch (status) {
      RideStatus.accepted || RideStatus.driverEnRoute => 'TO PICKUP',
      RideStatus.arrived => 'AT PICKUP',
      RideStatus.inProgress => 'TO DESTINATION',
      _ => 'TO DESTINATION',
    };
  }

  String _targetAddress(Ride ride) {
    return switch (ride.status) {
      RideStatus.inProgress => ride.dropoffAddress,
      _ => ride.pickupAddress,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeRideProvider);
    // When the backend tells us the ride has reached a terminal state,
    // navigate off this screen so the driver isn't stuck tapping buttons
    // that 400 every time.
    //
    //   - `completed`: replace this screen with the trip-summary so the
    //     driver lands on the earnings summary. Don't `clearRide()` here
    //     — DriverRideCompleteScreen reads the ride/state and clears it
    //     itself when the user dismisses.
    //   - `cancelled`: snackbar + clear state + pop. There's no summary
    //     screen for a cancelled ride.
    ref.listen<ActiveRideState>(activeRideProvider, (prev, next) {
      final wasActive = prev?.ride?.status.isActive ?? false;
      final nextStatus = next.ride?.status;
      if (!wasActive) return;
      if (!mounted) return;
      if (nextStatus == RideStatus.completed) {
        // Use GoRouter so the underlying nav stack stays consistent —
        // pushReplacement on a raw MaterialPageRoute would replace the
        // GoRoute entry and leave nothing on the stack to pop back to,
        // which is the "black screen on back" the driver was seeing.
        context.go('/ride-complete');
        return;
      }
      if (nextStatus == RideStatus.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This ride was cancelled.')),
        );
        ref.read(activeRideProvider.notifier).clearRide();
        // GoRouter (idempotent) — `Navigator.pop` here previously raced
        // with `_confirmAndCancel`'s own pop and crashed with "popped the
        // last page off of the stack" because the active-ride screen was
        // pushed via a raw MaterialPageRoute outside GoRouter's matchList.
        context.go('/home');
      }
    });

    final ride = state.ride;
    if (ride == null) {
      return const Scaffold(
        body: Center(child: Text('No active ride')),
      );
    }
    final isUpdating = state.isUpdating;
    final target = _routingTarget(ride);
    final targetLabel = _targetLabel(ride.status);
    final targetAddress = _targetAddress(ride);

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: Stack(
        children: [
          // ── Full-screen navigation map. Owns its own controller, GPS
          //    subscription, and Directions cache; rebuilding the parent
          //    Stack does not churn the platform-view bridge.
          Positioned.fill(
            child: RepaintBoundary(
              child: _NavigationMap(
                target: target,
                handle: _mapHandle,
                metrics: _liveMetrics,
              ),
            ),
          ),

          // ── Navigation header — rebuilds on every metrics tick (cheap
          //    text only), independent of the GoogleMap.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<_LiveMetrics>(
              valueListenable: _liveMetrics,
              builder: (context, metrics, _) {
                return ManeuverBanner(
                  progress: metrics.progress,
                  fallbackDistanceMeters: metrics.distanceMeters,
                  fallbackEtaMinutes: metrics.etaMinutes,
                  fallbackAddress: targetAddress,
                  phaseLabel: targetLabel,
                );
              },
            ),
          ),

          // ── Map controls: recenter + voice mute + overflow + SOS ──
          Positioned(
            right: MyShopSpacing.md,
            top: MediaQuery.of(context).padding.top + 130,
            child: Column(
              children: [
                _MapControlButton(
                  icon: Icons.my_location,
                  onTap: () => _mapHandle.recenter?.call(),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                // Voice mute toggle — drivers asked for an off switch so
                // they can stop the spoken turn-by-turn coach without
                // killing it system-wide. State lives on the map handle
                // so the icon and the actual `NavVoiceCoach.muted` flag
                // stay in lockstep.
                ValueListenableBuilder<bool>(
                  valueListenable: _mapHandle.voiceMuted,
                  builder: (_, muted, __) => _MapControlButton(
                    icon: muted ? Icons.volume_off : Icons.volume_up,
                    onTap: () =>
                        _mapHandle.voiceMuted.value = !_mapHandle.voiceMuted.value,
                  ),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                // Cancel-ride lives in the overflow menu, but it's the
                // wrong escape hatch once the rider is on board —
                // they'd be left stranded mid-trip. Hide the kebab
                // during `in_progress`; emergencies route through SOS,
                // genuine in-trip terminations go through support.
                if (ride.status != RideStatus.inProgress) ...[
                  _MapControlButton(
                    icon: Icons.more_vert,
                    onTap: () => _showOverflowMenu(ride),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                ],
                _SosButton(
                  // Routes to the shared driver/artisan emergency screen.
                  // That screen reads the active role + active booking
                  // and POSTs /emergency before dialing 191 — same flow
                  // the floating SOS button on the artisan side uses.
                  onTap: () => context.push('/safety/emergency'),
                ),
              ],
            ),
          ),

          // ── Bottom passenger panel (draggable sheet) ──
          // Sheet starts at a small peek (driver always has a grab handle)
          // and the proximity timer animates it up to the preview size
          // shortly after the screen mounts. The minimum is fixed at the
          // peek so a careless swipe-down can't dismiss the panel entirely
          // — without this the driver could swipe it off screen and have
          // no way to bring it back during an active trip.
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _peekSize,
            minChildSize: _peekSize,
            maxChildSize: 0.78,
            snap: true,
            snapSizes: const [_peekSize, _previewSize, 0.78],
            builder: (context, scrollController) {
              return _PassengerPanel(
                ride: ride,
                scrollController: scrollController,
                isUpdating: isUpdating,
                onPrimaryAction: () => _handlePrimaryAction(ride),
                onNavigate: () => _onNavigatePressed(ride),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Old `_NavigationHeader` lived here — replaced by `ManeuverBanner` from
// `core/widgets/maneuver_banner.dart`. The banner now renders the next
// turn (icon + distance + instruction) when Directions API steps are
// available, and falls back to the previous distance/ETA card when
// they aren't.

// ─── Live metrics + map handle ──────────────────────────────────────────────

class _LiveMetrics {
  const _LiveMetrics({this.distanceMeters, this.etaMinutes, this.progress});

  /// Straight-line distance from current GPS to the routing target, in
  /// meters. Null until we get the first fix.
  final double? distanceMeters;

  /// Estimated minutes remaining, derived from the Directions route's
  /// average road speed applied to [distanceMeters].
  final int? etaMinutes;

  /// Live navigation progress — current step, distance to the next
  /// maneuver, upcoming step. Drives the Google-Maps-style banner.
  /// Null on the fallback straight-line route (Directions API not
  /// available) — the banner falls back to a plain distance/ETA card.
  final NavProgress? progress;
}

/// Recenter shim — handed to [_NavigationMap] so it can register a callback
/// the parent can fire without holding the native controller itself.
class _MapHandle {
  VoidCallback? recenter;

  /// True when the driver has muted voice prompts. The map widget
  /// watches this and flips its `NavVoiceCoach.muted` flag in sync.
  /// Owned by the parent screen so the control-button icon stays
  /// in lockstep with the actual mute state.
  final ValueNotifier<bool> voiceMuted = ValueNotifier<bool>(false);
}

// ─── Navigation map ─────────────────────────────────────────────────────────
//
// Owns the GoogleMap, its controller, the Directions route cache, and the
// GPS subscription. Crucially this widget is the only thing that watches
// `driverLocationStreamProvider`, so a new fix triggers a setState INSIDE
// this widget only — the parent Stack doesn't rebuild and the platform-view
// bridge isn't churned every second.
//
// Mirrors the artisan-side _NavigationMap in active_job_screen.dart.

class _NavigationMap extends ConsumerStatefulWidget {
  const _NavigationMap({
    required this.target,
    required this.handle,
    required this.metrics,
  });

  final LatLng target;
  final _MapHandle handle;
  final ValueNotifier<_LiveMetrics> metrics;

  @override
  ConsumerState<_NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends ConsumerState<_NavigationMap> {
  GoogleMapController? _mapController;
  DirectionsRoute? _route;
  bool _routeLoading = false;

  /// Origin (driver GPS) used when the last route was fetched — lets us skip
  /// a refetch if the GPS fix has barely moved.
  LatLng? _lastRouteOrigin;
  DateTime? _lastRouteFetchAt;

  /// Most recent GPS fix. Stored in a field rather than via ref.watch so the
  /// GoogleMap only rebuilds when this widget calls setState.
  LatLng? _driver;

  /// Turn-by-turn nav mode. When true, the camera follows the driver on
  /// every GPS fix — tilted 3-D view, rotated to match the driver's
  /// heading, zoomed in close. Drivers get the same UX they'd see in
  /// Google Maps' "Start" mode without leaving the app.
  ///
  /// Flips to false the moment the driver drags or pinches the map (so
  /// we don't fight their gesture). The recenter button restores it.
  bool _followCamera = true;

  /// Last heading we used for the camera bearing. GPS `heading` is NaN
  /// when stationary and noisy at very low speeds, so we keep the
  /// previous good value rather than spin the camera wildly.
  double _lastBearing = 0;

  /// True while the camera is mid-animation triggered by THIS widget —
  /// `onCameraMoveStarted` fires for our own animateCamera calls too, so
  /// without this flag the very animation that follows the driver would
  /// flip `_followCamera` off and break the next fix.
  bool _programmaticCameraMove = false;

  Set<Marker> _markers = const <Marker>{};
  Set<Polyline> _polylines = const <Polyline>{};

  static const _routeRefreshMeters = 80.0;
  static const _routeRefreshThrottle = Duration(seconds: 30);

  /// Driver is "off-route" once they're this far from the nearest point
  /// on the route polyline. At that distance the Directions API's snap
  /// margin can no longer plausibly account for the gap — either they
  /// took a different turn or they're on a road the route doesn't know
  /// about. Either way we re-fetch the route from their current
  /// position.
  static const _offRouteThresholdMeters = 65.0;

  /// Camera params for nav mode. Top-down 2D pose with the camera
  /// rotated to match the direction of travel — same look as Google
  /// Maps' "Start" mode when the driver toggles off the 3D tilt. Zoom
  /// 17.5 keeps the next turn comfortably in view at city speeds.
  static const _navZoom = 17.5;
  static const _navTilt = 0.0;

  /// Spoken turn-by-turn coach — fires "in 200m, turn left" prompts at
  /// the same thresholds Google Maps uses. Owned per-map-state so it
  /// disposes with the screen and stops talking when the driver leaves
  /// the active ride.
  final NavVoiceCoach _voice = NavVoiceCoach();

  /// Triangular blue chevron used for the driver marker — same shape
  /// Google Maps uses in nav mode. Loaded async on init so the first
  /// frame can fall back to the default azure pin while the bitmap
  /// renders; once loaded, every subsequent `_buildMarkers` uses it
  /// with `rotation` set to the live bearing.
  BitmapDescriptor? _driverArrowIcon;

  @override
  void initState() {
    super.initState();
    widget.handle.recenter = _handleRecenter;
    widget.handle.voiceMuted.addListener(_onVoiceMuteChanged);
    _voice.muted = widget.handle.voiceMuted.value;
    _markers = _buildMarkers();
    // Render the navigation chevron in the background. The first map
    // frame uses the default azure pin; the moment the bitmap lands we
    // rebuild markers with the rotating chevron. Cached across screens
    // via NavArrowIcon._cached, so a second open is instant.
    NavArrowIcon.load().then((icon) {
      if (!mounted) return;
      setState(() {
        _driverArrowIcon = icon;
        _markers = _buildMarkers();
      });
    });
  }

  void _onVoiceMuteChanged() {
    _voice.muted = widget.handle.voiceMuted.value;
  }

  @override
  void didUpdateWidget(covariant _NavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Phase changed (e.g. pickup → dropoff after trip starts). Drop the
    // cached route + refit the camera so we navigate to the new target.
    if (oldWidget.target.latitude != widget.target.latitude ||
        oldWidget.target.longitude != widget.target.longitude) {
      _route = null;
      _lastRouteOrigin = null;
      _lastRouteFetchAt = null;
      _markers = _buildMarkers();
      _polylines = const <Polyline>{};
      // New leg → new set of maneuvers. Wipe the spoken-step memory so
      // the first turn on the new route gets announced.
      _voice.reset();
      final driver = _driver;
      if (driver != null) {
        _refreshRouteIfNeeded(driver, force: true);
        // Snap the camera onto the driver with nav pose so the new
        // leg starts in follow-mode rather than a static frame from
        // the previous leg.
        _followCamera = true;
        _animateCameraToDriver(driver, _lastBearing);
      }
      // `didUpdateWidget` runs inside the build pipeline; publishing metrics
      // here would synchronously notify a `ValueListenableBuilder` higher
      // up the tree and trip "setState called during build". Defer to the
      // next frame so the rebuild happens cleanly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _publishMetrics();
      });
    }
  }

  @override
  void dispose() {
    if (widget.handle.recenter == _handleRecenter) {
      widget.handle.recenter = null;
    }
    widget.handle.voiceMuted.removeListener(_onVoiceMuteChanged);
    _voice.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _handleRecenter() {
    final driver = _driver;
    if (driver == null) return;
    // Restore nav-mode follow: snap back to the driver with the same
    // 3-D tilted camera the position-fix loop uses, and refresh the
    // route in case the user drifted off-screen long enough that the
    // cached polyline is stale.
    _followCamera = true;
    _animateCameraToDriver(driver, _lastBearing);
    _refreshRouteIfNeeded(driver, force: true);
  }

  /// Animate the camera into nav-mode pose (tilted + rotated + zoomed).
  /// Wrapped in the `_programmaticCameraMove` guard so `onCameraMoveStarted`
  /// doesn't mistake our own animation for a user gesture and flip
  /// `_followCamera` off mid-flight.
  void _animateCameraToDriver(LatLng position, double bearing) {
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
    // The Google Maps SDK doesn't expose an "animation finished" callback,
    // so we drop the guard on the next frame. By then `onCameraMoveStarted`
    // has fired (it's synchronous-ish with the animation start) and a
    // genuine user gesture later won't be misattributed.
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
            destination: widget.target,
          );
      if (!mounted) return;
      setState(() {
        _route = route;
        _lastRouteOrigin = origin;
        _polylines = _buildPolylines();
      });
      // Deliberately NO `_fitCamera` here. The polyline draws itself on
      // top of the map; the camera is owned exclusively by the nav-
      // follow path in `_onPositionFix`. The earlier re-fit-on-every-
      // route-refresh was what kept yanking the camera back to a wide
      // two-pin bounds view and breaking nav mode.
      _publishMetrics();
    } finally {
      _routeLoading = false;
    }
  }

  void _onPositionFix(Position pos) {
    if (!mounted) return;
    final next = LatLng(pos.latitude, pos.longitude);
    final prev = _driver;

    if (prev != null &&
        prev.latitude == next.latitude &&
        prev.longitude == next.longitude) {
      return;
    }

    // Heading is NaN when the GPS doesn't have a directional fix (e.g.
    // stationary) and noisy below ~1 m/s. Keep the previous bearing in
    // those cases so the camera doesn't spin while the driver waits at
    // a red light.
    final bearing = (pos.heading.isFinite && pos.speed >= 1.0)
        ? pos.heading
        : _lastBearing;
    _lastBearing = bearing;

    setState(() {
      _driver = next;
      _markers = _buildMarkers();
    });

    // Turn-by-turn behaviour: as long as the driver hasn't grabbed the
    // map themselves, the camera follows them with a 3-D tilted view
    // pointing in the direction of travel. Same UX as Google Maps' nav
    // mode — but inline, no app switch needed. No `_hasFittedCamera`
    // gate — we want the nav pose engaged from the very first GPS fix,
    // not after a slow route-fetch round trip.
    if (_followCamera) {
      _animateCameraToDriver(next, bearing);
    }

    _publishMetrics();
    _refreshRouteIfNeeded(next);
  }

  void _publishMetrics() {
    final driver = _driver;
    if (driver == null) {
      widget.metrics.value = const _LiveMetrics();
      return;
    }
    final distance = _haversineMeters(driver, widget.target);
    final route = _route;
    final progress = route != null
        ? NavGuidance.progressFor(driver: driver, route: route)
        : null;
    widget.metrics.value = _LiveMetrics(
      distanceMeters: distance,
      etaMinutes: _liveEtaMinutes(distance, route),
      progress: progress,
    );

    // Voice prompts — only when we have a real maneuver to speak about.
    if (progress != null && progress.currentStep != null) {
      _voice.announce(progress);
    }

    // Off-route detection. The driver has wandered far enough from the
    // route polyline that we should recompute from their current GPS.
    // Bypasses the throttle because waiting 30s with stale directions
    // means the banner is lying to the driver about what to do next.
    final offBy = progress?.offRouteMeters;
    if (offBy != null && offBy > _offRouteThresholdMeters && !_routeLoading) {
      _voice.reset();
      _refreshRouteIfNeeded(driver, force: true);
    }
  }

  Set<Marker> _buildMarkers() {
    final driver = _driver;
    final arrow = _driverArrowIcon;
    return <Marker>{
      Marker(
        markerId: const MarkerId('target'),
        position: widget.target,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          // Custom chevron once it's loaded, default azure pin until
          // then so the first frame isn't empty.
          icon: arrow ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          // Rotate the chevron to match the direction of travel. Marker
          // rotation is independent of the camera bearing, so this
          // works in 2D top-down: the arrow always points where the
          // driver is heading on the map, while the camera spins to
          // keep "up = ahead". Anchor at center so rotation pivots
          // around the chevron's middle rather than the default
          // bottom-center used by drop pins.
          rotation: arrow != null ? _lastBearing : 0,
          anchor: const Offset(0.5, 0.5),
          flat: true,
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

  // Removed `_fitCamera` (bounds-fit of [driver, target]). It used to
  // run on map creation and on phase change, and its animation fired
  // `onCameraMoveStarted` without the programmatic guard — which
  // silently flipped `_followCamera` off and stranded the camera in a
  // static two-pin overview. Nav mode now owns the camera from the
  // very first GPS fix; the driver sees themselves in the centre with
  // the polyline pointing forward, the way Google Maps' "Start" mode
  // opens.

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Position>>(driverLocationStreamProvider,
        (prev, next) {
      next.whenData(_onPositionFix);
    });

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _driver ?? widget.target,
        zoom: 14,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        final driver = _driver;
        if (driver != null) {
          // Jump straight to nav-mode pose (follow + bearing + 2D
          // top-down) instead of a wide bounds fit of [driver, target].
          // The bounds fit fired `onCameraMoveStarted` without the
          // programmatic guard, which silently flipped `_followCamera`
          // off and left the user staring at the static two-pin view
          // — that's the bug the driver reported as "just shows the
          // two points, no live navigation".
          _animateCameraToDriver(driver, _lastBearing);
        }
      },
      // User-initiated pan / pinch → pause nav-mode follow so we don't
      // fight their gesture. The recenter button restores it. Programmatic
      // camera moves (our own animateCamera) carry the guard so we don't
      // accidentally pause ourselves mid-animation.
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
        top: MediaQuery.of(context).padding.top + 100,
        bottom: 220,
      ),
      markers: _markers,
      polylines: _polylines,
    );
  }

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

  /// Estimated minutes derived from the Directions response's average road
  /// speed. Falls back to ~30 km/h until we have a real route.
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
    mps ??= 8.333;
    return (meters / mps / 60).round();
  }
}

// ─── Map controls ───────────────────────────────────────────────────────────

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: MyShopColors.darkSlate),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: MyShopColors.error,
          shape: BoxShape.circle,
          border: Border.all(color: MyShopColors.surfaceWhite, width: 3),
          boxShadow: [
            BoxShadow(
              color: MyShopColors.error.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 16, color: Colors.white),
            Text('SOS',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─── Passenger panel ────────────────────────────────────────────────────────

class _PassengerPanel extends StatelessWidget {
  const _PassengerPanel({
    required this.ride,
    required this.scrollController,
    required this.isUpdating,
    required this.onPrimaryAction,
    required this.onNavigate,
  });

  final Ride ride;
  final ScrollController scrollController;
  final bool isUpdating;
  final VoidCallback onPrimaryAction;

  /// Re-launches Google Maps with directions to the current target
  /// (pickup before in_progress, dropoff after). Kept as an explicit
  /// button so the driver isn't stranded if they kill the maps app and
  /// return to the MyShop screen.
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 30,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              MyShopSpacing.md, 12, MyShopSpacing.md, MyShopSpacing.md),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: MyShopColors.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // Passenger row: avatar / name+rating / chat / phone
            Row(
              children: [
                Stack(
                  children: [
                    _ClientAvatar(photoUrl: ride.clientPhotoUrl, size: 56),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: MyShopColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: MyShopColors.surfaceWhite, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ride.clientName ?? 'Passenger',
                        style: const TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: MyShopColors.primaryGoldLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 12, color: MyShopColors.ratingStar),
                            const SizedBox(width: 3),
                            Text(
                              (ride.clientRating ?? 4.9).toStringAsFixed(1),
                              style: const TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: MyShopColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _ChatContactButton(
                  rideId: ride.id,
                  riderName: ride.clientName ?? 'Passenger',
                ),
                // Phone `_ContactButton` removed in v1.0 — masked calls
                // deferred to v1.2. Chat is the peer comms channel.
              ],
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // Trip stepper
            _TripStepper(status: ride.status),
            const SizedBox(height: MyShopSpacing.md),

            // Pickup → Destination card with FARE
            Container(
              padding: const EdgeInsets.all(MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoutePoint(
                    colorRing: MyShopColors.darkSlate,
                    label: 'PICKUP POINT',
                    address: ride.pickupAddress,
                  ),
                  // Intermediate stops the rider added (mid-trip or
                  // at booking). The driver sees them in route order
                  // between pickup and destination so the next-stop
                  // address is always obvious — these rows mirror
                  // exactly what the rider's "Edit your trip" sheet
                  // shows.
                  for (final stop in ride.stops) ...[
                    Container(
                      width: 1.5,
                      height: 14,
                      margin: const EdgeInsets.only(left: 9, top: 2, bottom: 2),
                      child: const _DottedVerticalLine(),
                    ),
                    _RoutePoint(
                      colorRing: MyShopColors.warning,
                      label: 'STOP',
                      address: stop.address,
                    ),
                  ],
                  Container(
                    width: 1.5,
                    height: 14,
                    margin: const EdgeInsets.only(left: 9, top: 2, bottom: 2),
                    child: const _DottedVerticalLine(),
                  ),
                  _RoutePoint(
                    colorRing: MyShopColors.primaryGold,
                    label: 'DESTINATION',
                    address: ride.dropoffAddress,
                  ),
                  const SizedBox(height: 12),
                  const Divider(
                      height: 0.5, thickness: 0.5, color: MyShopColors.divider),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FARE',
                          style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: MyShopColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ride.estimatedFareDisplay,
                          style: const TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: MyShopColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // Navigate (re-)launcher — auto-fired on accept / start trip,
            // but kept here as an explicit button so the driver can re-
            // launch Google Maps if it crashes or they swipe it away.
            // Labels the current target so it's clear where it'll route.
            OutlinedButton.icon(
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text(
                ride.status == RideStatus.inProgress
                    ? 'NAVIGATE TO DROPOFF'
                    : 'NAVIGATE TO PICKUP',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.darkSlate,
                side: const BorderSide(color: MyShopColors.divider),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),

            // Primary action button
            ElevatedButton(
              onPressed: isUpdating ? null : onPrimaryAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.darkSlate,
                foregroundColor: MyShopColors.textOnPrimary,
                disabledBackgroundColor:
                    MyShopColors.darkSlate.withValues(alpha: 0.6),
                disabledForegroundColor: MyShopColors.textOnPrimary,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(40)),
                textStyle: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5),
                elevation: 4,
                shadowColor: MyShopColors.darkSlate.withValues(alpha: 0.4),
              ),
              child: isUpdating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation(MyShopColors.textOnPrimary),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_primaryActionLabel(ride.status)),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right, size: 22),
                      ],
                    ),
            ),
            const SizedBox(height: MyShopSpacing.sm),

            // Helper caption
            Text(
              _helperCaption(ride.status),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _primaryActionLabel(RideStatus status) {
    return switch (status) {
      RideStatus.accepted ||
      RideStatus.driverEnRoute =>
        'ARRIVED AT DESTINATION',
      RideStatus.arrived => 'START TRIP',
      RideStatus.inProgress => 'END TRIP',
      _ => 'CONTINUE',
    };
  }

  String _helperCaption(RideStatus status) {
    return switch (status) {
      RideStatus.accepted ||
      RideStatus.driverEnRoute =>
        'TAP ARRIVED WHEN YOU REACH THE PIN',
      RideStatus.arrived => 'TAP START WHEN PASSENGER IS IN THE VEHICLE',
      RideStatus.inProgress => 'TAP END WHEN PASSENGER HAS EXITED SAFELY',
      _ => '',
    };
  }
}

// ─── Contact buttons (chat) ─────────────────────────────────────────────────

/// Icon-sized chat affordance used in the passenger panel header. Auto-
/// opens the chat channel on the orchestrator (so the unread badge is live
/// without the user visiting `/chat` first) and routes to the chat screen
/// on tap.
class _ChatContactButton extends ConsumerStatefulWidget {
  const _ChatContactButton({
    required this.rideId,
    required this.riderName,
  });

  final String rideId;
  final String riderName;

  @override
  ConsumerState<_ChatContactButton> createState() => _ChatContactButtonState();
}

class _ChatContactButtonState extends ConsumerState<_ChatContactButton> {
  StreamSubscription<int>? _unreadSub;
  int _unread = 0;
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureOpened();
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _ensureOpened() {
    if (widget.rideId.isEmpty) return;
    final controller = ref.read(chatControllerProvider).valueOrNull;
    if (controller == null || _opened) return;
    _opened = true;
    scheduleMicrotask(() {
      if (!mounted) return;
      controller.openChannel(ChatBookingType.ride, widget.rideId);
    });
    _unreadSub = controller.unreadCountStream.listen((n) {
      if (!mounted) return;
      setState(() => _unread = n);
    });
  }

  void _onTap() {
    if (widget.rideId.isEmpty) return;
    context.push(
      '/chat',
      extra: <String, Object?>{
        'bookingType': ChatBookingType.ride,
        'bookingId': widget.rideId,
        'peerName': widget.riderName,
        'peerStatus': 'On the trip',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatControllerProvider);
    _ensureOpened();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: MyShopColors.darkSlate,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 20,
              color: MyShopColors.textOnPrimary,
            ),
          ),
        ),
        if (_unread > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: MyShopColors.error,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: MyShopColors.surfaceWhite,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _unread > 99 ? '99+' : _unread.toString(),
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textOnPrimary,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Trip stepper ───────────────────────────────────────────────────────────

class _TripStepper extends StatelessWidget {
  const _TripStepper({required this.status});
  final RideStatus status;

  int get _activeStep {
    return switch (status) {
      RideStatus.accepted || RideStatus.driverEnRoute => 0,
      RideStatus.arrived || RideStatus.inProgress => 1,
      RideStatus.completed => 2,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    const steps = [
      (label: 'PICKUP', icon: Icons.check),
      (label: 'ON TRIP', icon: Icons.navigation),
      (label: 'ARRIVAL', icon: Icons.location_on_outlined),
    ];

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _StepNode(
            icon: steps[i].icon,
            label: steps[i].label,
            isActive: i == _activeStep,
            isComplete: i < _activeStep,
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.only(bottom: 22),
                color: i < _activeStep
                    ? MyShopColors.primaryGold
                    : MyShopColors.divider,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isComplete,
  });
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final highlight = isActive || isComplete;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color:
                highlight ? MyShopColors.primaryGold : MyShopColors.surfaceGrey,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: highlight ? Colors.white : MyShopColors.disabled,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: highlight ? MyShopColors.textPrimary : MyShopColors.disabled,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

// ─── Route point row ────────────────────────────────────────────────────────

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({
    required this.colorRing,
    required this.label,
    required this.address,
  });

  final Color colorRing;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite,
            shape: BoxShape.circle,
            border: Border.all(color: colorRing, width: 2),
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colorRing,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DottedVerticalLine extends StatelessWidget {
  const _DottedVerticalLine();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(
        4,
        (_) => Container(
          width: 1.5,
          height: 2,
          color: MyShopColors.divider,
        ),
      ),
    );
  }
}

/// Round avatar that loads `photoUrl` over the network when available and
/// falls back to a generic person icon while loading or on error.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.photoUrl, required this.size});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) return _placeholder();
    final cacheDim = (size * 3).round();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cacheDim,
        memCacheHeight: cacheDim,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFFCEAE1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person,
        size: size * 0.5,
        color: MyShopColors.textSecondary,
      ),
    );
  }
}
