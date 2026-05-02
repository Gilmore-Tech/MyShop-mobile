import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/constants/mapbox_config.dart';
import '../../../core/providers/current_location_provider.dart';
import '../providers/artisan_live_location_provider.dart';
import '../providers/bid_detail_provider.dart';

// ── Tunables ───────────────────────────────────────────────────────────────────
// How long the artisan marker takes to slide from its current position to the
// freshly-polled one. Slightly less than the 10 s poll interval so motion
// finishes before the next update arrives, avoiding jerk.
const _markerInterpolationDuration = Duration(milliseconds: 8500);

/// Full-screen tracking map for an artisan who has bid on a job.
/// The artisan pin interpolates smoothly between polled positions (à la
/// Uber/Bolt). Live distance + ETA update in the bottom card on every frame.
class BidLocationMapScreen extends ConsumerWidget {
  final String jobId;
  final String bidId;
  const BidLocationMapScreen({
    super.key,
    required this.jobId,
    required this.bidId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (jobId: jobId, bidId: bidId);
    final bidAsync = ref.watch(bidDetailProvider(key));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: bidAsync.when(
        // Critical for the tracking UX: background refetches must NOT
        // unmount _TrackingBody, otherwise the map controller, the move
        // animation, and the camera-fit flags all reset — the user sees
        // the marker jump and the camera snap back every poll.
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(
          child: CircularProgressIndicator(color: MyShopColors.primaryGold),
        ),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load location',
          onRetry: () => ref.invalidate(bidDetailProvider(key)),
        ),
        data: (bid) => _TrackingBody(
          bid: bid,
          onBack: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

// ── Tracking body ─────────────────────────────────────────────────────────────
// Owns the map controller, the interpolation animation, and the camera-fit
// flags. Watches the live-location provider; when a new position arrives it
// starts a tween from the currently-displayed position to the target.

class _TrackingBody extends ConsumerStatefulWidget {
  final BidDetail bid;
  final VoidCallback onBack;
  const _TrackingBody({required this.bid, required this.onBack});

  @override
  ConsumerState<_TrackingBody> createState() => _TrackingBodyState();
}

class _TrackingBodyState extends ConsumerState<_TrackingBody>
    with SingleTickerProviderStateMixin {
  /// Ultimate fallback when we have neither job nor artisan coordinates AND
  /// no cached device fix. Kept as a const so it's never null.
  static const _kumasiFallback =
      LatLng(MapboxConfig.defaultLat, MapboxConfig.defaultLng);

  GoogleMapController? _mapController;
  bool _initialFitDone = false;
  bool _bothPointsFitDone = false;

  // Smooth marker interpolation.
  late final AnimationController _moveCtrl = AnimationController(
    vsync: this,
    duration: _markerInterpolationDuration,
  );
  LatLng? _tweenStart;
  LatLng? _tweenEnd;

  /// The position currently painted on the map for the artisan. Null until
  /// we have at least one known position (snapshot or live).
  LatLng? _displayedArtisan;

  /// The last target we kicked off an animation toward — used to detect when
  /// a new live emission differs from the previous one.
  LatLng? _lastTarget;

  @override
  void initState() {
    super.initState();
    // Seed from snapshot so the pin appears immediately without waiting for
    // the first poll.
    final snap = _snapshotArtisan;
    if (snap != null) {
      _displayedArtisan = snap;
      _lastTarget = snap;
    }

    _moveCtrl.addListener(_onMoveTick);
  }

  @override
  void dispose() {
    _moveCtrl.removeListener(_onMoveTick);
    _moveCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  LatLng? get _snapshotArtisan {
    final a = widget.bid.artisan;
    return a.hasLocation ? LatLng(a.latitude!, a.longitude!) : null;
  }

  LatLng? get _job {
    final b = widget.bid;
    return b.hasJobLocation ? LatLng(b.jobLatitude!, b.jobLongitude!) : null;
  }

  void _onMoveTick() {
    final start = _tweenStart;
    final end = _tweenEnd;
    if (start == null || end == null) return;
    final t = _moveCtrl.value;
    setState(() {
      _displayedArtisan = LatLng(
        start.latitude + (end.latitude - start.latitude) * t,
        start.longitude + (end.longitude - start.longitude) * t,
      );
    });
  }

  /// Begin animating from the current displayed position to [target]. If
  /// nothing is on-screen yet, snap without animating.
  void _animateTo(LatLng target) {
    final current = _displayedArtisan;
    if (current == null) {
      setState(() => _displayedArtisan = target);
      return;
    }
    _tweenStart = current;
    _tweenEnd = target;
    _moveCtrl
      ..stop()
      ..reset()
      ..forward();
  }

  void _fitBounds({required LatLng? job, required LatLng? artisan}) {
    final c = _mapController;
    if (c == null) return;

    if (job != null && artisan != null) {
      final sw = LatLng(
        job.latitude < artisan.latitude ? job.latitude : artisan.latitude,
        job.longitude < artisan.longitude ? job.longitude : artisan.longitude,
      );
      final ne = LatLng(
        job.latitude > artisan.latitude ? job.latitude : artisan.latitude,
        job.longitude > artisan.longitude ? job.longitude : artisan.longitude,
      );
      c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: sw, northeast: ne),
          96,
        ),
      );
      return;
    }
    final point = job ?? artisan;
    if (point != null) {
      c.animateCamera(CameraUpdate.newLatLngZoom(point, 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final topPad = MediaQuery.paddingOf(context).top;

    final bid = widget.bid;

    // Watch live location — this is the ONLY subscription here, so when the
    // 10 s poll emits, rebuild is scoped to _TrackingBody, not the parent.
    final live = ref.watch(artisanLiveLocationProvider(
      artisanLiveKey(jobId: bid.jobId, artisanId: bid.artisan.artisanId),
    ));

    // Resolve a target position: live wins, snapshot is the fallback.
    final targetArtisan =
        live != null ? LatLng(live.latitude, live.longitude) : _snapshotArtisan;

    // Kick off animation when the target moves (deferred so setState during
    // build doesn't throw).
    if (targetArtisan != null && !_latLngEq(targetArtisan, _lastTarget)) {
      _lastTarget = targetArtisan;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _animateTo(targetArtisan);
      });
    }

    final job = _job;
    final displayed = _displayedArtisan;

    // One-shot camera fit when both points first become available.
    if (!_bothPointsFitDone && job != null && displayed != null) {
      _bothPointsFitDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitBounds(job: job, artisan: displayed);
      });
    }

    final markers = <Marker>{
      if (job != null)
        Marker(
          markerId: const MarkerId('job'),
          position: job,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 1.0),
          infoWindow: const InfoWindow(title: 'Job site'),
        ),
      if (displayed != null)
        Marker(
          markerId: const MarkerId('artisan'),
          position: displayed,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 1.0),
          flat: false,
          infoWindow: InfoWindow(title: bid.artisan.name),
        ),
    };

    final polylines = <Polyline>{
      if (job != null && displayed != null)
        Polyline(
          polylineId: const PolylineId('route'),
          points: [displayed, job],
          color: MyShopColors.primaryGold,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
    };

    // Live metrics shown in the bottom card. Recomputed every animation tick
    // so the distance visibly ticks down as the pin slides toward the site.
    final double? distanceKm = (job != null && displayed != null)
        ? Geolocator.distanceBetween(
              job.latitude,
              job.longitude,
              displayed.latitude,
              displayed.longitude,
            ) /
            1000.0
        : null;
    final int etaMinutes = live?.etaMinutes ?? bid.artisan.etaMinutes;

    final cached = ref.watch(currentDevicePositionProvider);
    final cachedLatLng =
        cached == null ? null : LatLng(cached.latitude, cached.longitude);
    final initialCamera = CameraPosition(
      target: job ?? displayed ?? cachedLatLng ?? _kumasiFallback,
      zoom: 14,
    );

    return Stack(
      children: [
        // ── Map ─────────────────────────────────────────────────────────────
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: initialCamera,
            onMapCreated: (c) {
              _mapController = c;
              if (!_initialFitDone) {
                _initialFitDone = true;
                _fitBounds(job: job, artisan: displayed);
                if (job != null && displayed != null) {
                  _bothPointsFitDone = true;
                }
              }
            },
            markers: markers,
            polylines: polylines,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
          ),
        ),

        // ── Top bar: back + live badge ──────────────────────────────────────
        Positioned(
          top: topPad + h * 0.010,
          left: w * 0.041,
          right: w * 0.041,
          child: Row(
            children: [
              _CircleButton(
                icon: Icons.arrow_back,
                onTap: widget.onBack,
                w: w,
                h: h,
              ),
              const Spacer(),
              if (live != null) _LiveBadge(w: w, h: h),
            ],
          ),
        ),

        // ── Recenter FAB ────────────────────────────────────────────────────
        Positioned(
          right: w * 0.041,
          bottom:
              _bottomCardHeight(h, hasArtisan: displayed != null) + h * 0.024,
          child: _CircleButton(
            icon: Icons.my_location_rounded,
            onTap: () => _fitBounds(job: job, artisan: displayed),
            w: w,
            h: h,
          ),
        ),

        // ── Bottom info card ────────────────────────────────────────────────
        if (displayed != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ArtisanInfoCard(
              bid: bid,
              distanceKm: distanceKm,
              etaMinutes: etaMinutes,
              isLive: live != null,
              w: w,
              h: h,
            ),
          )
        else
          _MissingArtisanBanner(w: w, h: h),
      ],
    );
  }

  /// Rough estimate used to place the recenter FAB above whichever bottom
  /// element is showing.
  double _bottomCardHeight(double h, {required bool hasArtisan}) =>
      hasArtisan ? h * 0.26 : h * 0.12;
}

bool _latLngEq(LatLng a, LatLng? b) {
  if (b == null) return false;
  return a.latitude == b.latitude && a.longitude == b.longitude;
}

// ── Artisan info card (Uber-style) ────────────────────────────────────────────

class _ArtisanInfoCard extends StatelessWidget {
  final BidDetail bid;
  final double? distanceKm;
  final int etaMinutes;
  final bool isLive;
  final double w;
  final double h;
  const _ArtisanInfoCard({
    required this.bid,
    required this.distanceKm,
    required this.etaMinutes,
    required this.isLive,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final a = bid.artisan;

    return Container(
      padding: EdgeInsets.fromLTRB(
        w * 0.051,
        h * 0.024,
        w * 0.051,
        bottomPad + h * 0.019,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(w * 0.061),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── ETA headline (the thing the client cares about) ─────────────
          _EtaHeadline(
            etaMinutes: etaMinutes,
            distanceKm: distanceKm,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.017),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.017),

          // ── Artisan identity row ────────────────────────────────────────
          Row(
            children: [
              _Avatar(artisan: a, w: w),
              SizedBox(width: w * 0.036),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.name,
                            style: TextStyle(
                              fontSize: w * 0.043,
                              fontWeight: FontWeight.w700,
                              color: MyShopColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (a.isKycVerified) ...[
                          SizedBox(width: w * 0.010),
                          Icon(
                            Icons.verified_rounded,
                            size: w * 0.041,
                            color: MyShopColors.success,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: h * 0.003),
                    if (a.tradeTitle.isNotEmpty)
                      Text(
                        a.tradeTitle,
                        style: TextStyle(
                          fontSize: w * 0.031,
                          fontWeight: FontWeight.w500,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    SizedBox(height: h * 0.006),
                    if (a.reviewCount > 0)
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: w * 0.036,
                            color: MyShopColors.primaryGold,
                          ),
                          SizedBox(width: w * 0.010),
                          Text(
                            a.rating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: w * 0.031,
                              fontWeight: FontWeight.w600,
                              color: MyShopColors.textPrimary,
                            ),
                          ),
                          Text(
                            ' (${a.reviewCount})',
                            style: TextStyle(
                              fontSize: w * 0.028,
                              color: MyShopColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EtaHeadline extends StatelessWidget {
  final int etaMinutes;
  final double? distanceKm;
  final double w;
  final double h;
  const _EtaHeadline({
    required this.etaMinutes,
    required this.distanceKm,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final hasEta = etaMinutes > 0;
    final hasDistance = distanceKm != null && distanceKm! > 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasEta ? 'ARRIVING IN' : 'ARTISAN LOCATION',
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: h * 0.006),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasEta) ...[
                    Text(
                      '$etaMinutes',
                      style: TextStyle(
                        fontSize: w * 0.113, // ~44sp
                        fontWeight: FontWeight.w800,
                        color: MyShopColors.textPrimary,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(width: w * 0.015),
                    Padding(
                      padding: EdgeInsets.only(bottom: h * 0.008),
                      child: Text(
                        'min',
                        style: TextStyle(
                          fontSize: w * 0.041,
                          fontWeight: FontWeight.w600,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ),
                  ] else
                    Text(
                      hasDistance
                          ? '${distanceKm!.toStringAsFixed(1)} km away'
                          : 'Tracking...',
                      style: TextStyle(
                        fontSize: w * 0.051,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                ],
              ),
              if (hasEta && hasDistance) ...[
                SizedBox(height: h * 0.005),
                Text(
                  '${distanceKm!.toStringAsFixed(1)} km to your location',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          width: w * 0.128,
          height: w * 0.128,
          decoration: BoxDecoration(
            color: MyShopColors.primaryGold.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.near_me_rounded,
            size: w * 0.067,
            color: MyShopColors.primaryGold,
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final BidArtisanProfile artisan;
  final double w;
  const _Avatar({required this.artisan, required this.w});

  String get _initials {
    final parts = artisan.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final size = w * 0.138; // ~54dp
    final photo = artisan.profilePhotoUrl;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: artisan.avatarColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: w * 0.046,
          fontWeight: FontWeight.w700,
          color: MyShopColors.surfaceWhite,
        ),
      ),
    );

    if (photo == null || photo.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        photo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

// ── Shared chrome ─────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _CircleButton({
    required this.icon,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: w * 0.113,
        height: w * 0.113,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: w * 0.054, color: MyShopColors.textPrimary),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  final double w;
  final double h;
  const _LiveBadge({required this.w, required this.h});

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

/// Pulsing dot — the tiny touch that makes the map feel alive on every
/// poll tick.
class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final h = widget.h;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.028, vertical: h * 0.007),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.051),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: w * 0.021,
              height: w * 0.021,
              decoration: BoxDecoration(
                color: MyShopColors.success.withValues(
                  alpha: 0.4 + 0.6 * _pulse.value,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: w * 0.015),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w800,
              color: MyShopColors.success,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingArtisanBanner extends StatelessWidget {
  final double w;
  final double h;
  const _MissingArtisanBanner({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: w * 0.041,
      right: w * 0.041,
      bottom: bottomPad + h * 0.019,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.014,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.031),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: w * 0.046, color: MyShopColors.textSecondary),
            SizedBox(width: w * 0.026),
            Expanded(
              child: Text(
                "Artisan's location isn't available yet. Showing the job site only.",
                style: TextStyle(
                  fontSize: w * 0.031,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
