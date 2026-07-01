import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../../core/services/directions_service.dart';
import '../../../core/widgets/route_warning_banner.dart';

/// Full-screen trip summary modal shown when a trip card is tapped.
///
/// On open, the modal fires two parallel fetches:
///   * `GET /rides/:id` to populate the real fare breakdown (the list
///     endpoint only carries the headline total).
///   * `DirectionsService.fetchRoute(pickup, dropoff)` to draw the route
///     line between the two pins on the inline Google Map.
///
/// Both are best-effort: a network failure on either leaves the UI in a
/// degraded-but-honest state (dashes on the breakdown lines, straight-
/// line fallback on the route).
class TripDetailModal extends ConsumerStatefulWidget {
  const TripDetailModal({super.key, required this.trip});

  final TripDetailData trip;

  /// Show this modal as a centered dialog overlay with dark scrim.
  static Future<void> show(BuildContext context, TripDetailData trip) {
    return showDialog(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => TripDetailModal(trip: trip),
    );
  }

  @override
  ConsumerState<TripDetailModal> createState() => _TripDetailModalState();
}

class _TripDetailModalState extends ConsumerState<TripDetailModal> {
  /// Full snapshot from `GET /rides/:id` — the only payload that carries
  /// the pickup/dropoff coordinates (the list endpoint's `findMany` can't
  /// project PostGIS geometry, so the Ride model on a list row arrives
  /// with lat/lng = 0) and the per-line fare breakdown. Fetched on every
  /// open regardless of status because we want the map for cancelled
  /// rides too.
  ///
  /// Null until the fetch returns or forever if the call fails — the
  /// map falls back to a placeholder, and the breakdown lines render
  /// as dashes.
  _RideSnapshot? _snapshot;

  /// Passenger identity pulled from the same `GET /rides/:id` snapshot. The
  /// backend exposes the rider's real, dialable number on completed-ride
  /// snapshots for a limited window so the driver can reconnect (e.g. a
  /// forgotten item); both stay null when the payload omits them / the
  /// window has closed.
  String? _clientName;
  String? _clientPhone;

  bool get _isCompleted => widget.trip.status.toLowerCase() == 'completed';

  @override
  void initState() {
    super.initState();
    _fetchSnapshot();
  }

  Future<void> _fetchSnapshot() async {
    try {
      final raw =
          await ref.read(rideServiceProvider).getRide(widget.trip.rideId);
      if (!mounted) return;
      final clientObj = raw['client'] as Map<String, dynamic>?;
      setState(() {
        _snapshot = _RideSnapshot.fromJson(raw);
        _clientName = (raw['clientName'] ??
                clientObj?['name'] ??
                clientObj?['fullName']) as String?;
        _clientPhone = (raw['clientPhone'] ??
                clientObj?['phone'] ??
                clientObj?['maskedPhone']) as String?;
      });
    } catch (_) {
      // Network / 404 — leave _snapshot null. The placeholder map + dashes
      // are intentional; a noisy banner on an info-only screen would be
      // more disruptive than the missing data.
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final pickupLat = snap?.pickupLat ?? 0;
    final pickupLng = snap?.pickupLng ?? 0;
    final dropoffLat = snap?.dropoffLat ?? 0;
    final dropoffLng = snap?.dropoffLng ?? 0;
    final hasCoords = (pickupLat != 0 || pickupLng != 0) &&
        (dropoffLat != 0 || dropoffLng != 0);

    return Center(
      child: Container(
        width: 358,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        margin: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 50,
              offset: Offset(0, 25),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: MyShopColors.surfaceWhite,
            child: Stack(
              children: [
                // The map gets a fixed slot at the top of a Column rather
                // than living inside a ListView. Platform views (which
                // GoogleMap is) need a parent-anchored, finite-size box
                // — inside a shrink-wrapping list view the native view
                // can fail to attach and render as a blank slot. Only the
                // content below scrolls.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 1. Map preview with distance badge ──
                    // Until the snapshot lands we render the flat
                    // placeholder. The map mounts only once with real
                    // coords so the native view doesn't have to be
                    // re-anchored mid-flight. A ValueKey on the coords
                    // guarantees a fresh widget per ride if this modal
                    // ever reopens for a different ride id.
                    if (hasCoords)
                      _MapPreview(
                        key: ValueKey(
                            '$pickupLat,$pickupLng-$dropoffLat,$dropoffLng'),
                        distanceKm: widget.trip.distanceKm,
                        pickupLat: pickupLat,
                        pickupLng: pickupLng,
                        dropoffLat: dropoffLat,
                        dropoffLng: dropoffLng,
                      )
                    else
                      _MapPlaceholder(distanceKm: widget.trip.distanceKm),

                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: MyShopSpacing.md),

                                  // ── 2. Trip ID + Status badge ──
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _TripIdTag(tripId: widget.trip.tripId),
                                      _StatusBadge(status: widget.trip.status),
                                    ],
                                  ),
                                  const SizedBox(height: MyShopSpacing.sm),

                                  // ── 3. Trip Summary heading ──
                                  const Text(
                                    'Trip Summary',
                                    style: TextStyle(
                                      fontFamily: 'Raleway',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: MyShopColors.textPrimary,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: MyShopSpacing.sm),

                                  // ── 4. Date + Time ──
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 12,
                                          color: MyShopColors.textSecondary),
                                      const SizedBox(width: 8),
                                      Text(widget.trip.date, style: _metaStyle),
                                      const SizedBox(width: 12),
                                      const Text('•',
                                          style: TextStyle(
                                              color: MyShopColors.textSecondary,
                                              fontSize: 12)),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.access_time,
                                          size: 12,
                                          color: MyShopColors.textSecondary),
                                      const SizedBox(width: 8),
                                      Text(widget.trip.timeRange,
                                          style: _metaStyle),
                                    ],
                                  ),
                                  const SizedBox(height: MyShopSpacing.lg),

                                  // ── 5. Route: Pickup → Dropoff ──
                                  _RouteSection(
                                    pickupTime: widget.trip.pickupTime,
                                    pickupAddress: widget.trip.pickupAddress,
                                    dropoffTime: widget.trip.dropoffTime,
                                    dropoffAddress: widget.trip.dropoffAddress,
                                  ),
                                  const SizedBox(height: MyShopSpacing.lg),

                                  // ── 5b. Passenger contact (post-trip
                                  // window only — number drops to null once
                                  // it closes) ──
                                  if ((_clientPhone ?? '').trim().isNotEmpty) ...[
                                    _PassengerContactRow(
                                      name: _clientName ?? 'Passenger',
                                      phone: _clientPhone!,
                                    ),
                                    const SizedBox(height: MyShopSpacing.lg),
                                  ],
                                ],
                              ),
                            ),

                            // ── 6. Fare Breakdown card ──
                            const Divider(
                                height: 1, color: MyShopColors.divider),
                            if (_isCompleted)
                              _FareBreakdownCard(
                                trip: widget.trip,
                                snapshot: _snapshot,
                              )
                            else
                              _CancelledFareNotice(status: widget.trip.status),
                            const SizedBox(height: MyShopSpacing.md),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // ── X close button (sits above the map) ──
                Positioned(
                  top: 8,
                  right: 8,
                  child: _CloseButton(
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _metaStyle = TextStyle(
    fontFamily: 'Raleway',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: MyShopColors.textSecondary,
  );
}

// ─── Passenger contact row ──────────────────────────────────────────────────

/// Compact rider identity + "Call" affordance shown on a completed trip's
/// detail while the backend still serves the rider's real number (post-trip
/// reconnect window). Hidden entirely once the number drops to null.
class _PassengerContactRow extends StatelessWidget {
  const _PassengerContactRow({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.sm),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: MyShopColors.darkSlate,
            child: Icon(Icons.person_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          MyShopCallButton(phoneNumber: phone, semanticLabel: 'Call passenger'),
        ],
      ),
    );
  }
}

// ─── Close (X) button ───────────────────────────────────────────────────────

/// Floating circular X button overlaid on the top-right of the modal so
/// users have an explicit way to dismiss in addition to the barrier tap.
/// Semi-transparent black so it remains legible whether the map preview
/// underneath is light (no coords → grey placeholder) or imagery-heavy.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.close, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

// ─── Map Preview ────────────────────────────────────────────────────────────

/// Inline Google Map showing the trip's pickup pin, dropoff pin, and the
/// route line between them. Caller (the modal) only constructs this when
/// real coordinates are available — until then a [_MapPlaceholder] is
/// shown instead so the native map view isn't asked to render with
/// (0,0) origin.
///
/// All map gestures are disabled so the modal can be scrolled past
/// without the map stealing the touch.
class _MapPreview extends ConsumerStatefulWidget {
  const _MapPreview({
    super.key,
    required this.distanceKm,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
  });

  final String distanceKm;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;

  @override
  ConsumerState<_MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends ConsumerState<_MapPreview> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = const <Polyline>{};
  String? _routeWarning;

  @override
  void initState() {
    super.initState();
    // Seed with a straight line so the route is visible immediately,
    // even before Directions responds. The Directions polyline replaces
    // it once available; if Directions fails the straight line stays.
    _polylines = {
      Polyline(
        polylineId: const PolylineId('trip-route'),
        points: [
          LatLng(widget.pickupLat, widget.pickupLng),
          LatLng(widget.dropoffLat, widget.dropoffLng),
        ],
        color: MyShopColors.primaryGold,
        width: 4,
      ),
    };
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    try {
      final route = await ref.read(directionsServiceProvider).fetchRoute(
            origin: LatLng(widget.pickupLat, widget.pickupLng),
            destination: LatLng(widget.dropoffLat, widget.dropoffLng),
          );
      // Diagnostic — tells us at a glance whether Directions returned a
      // real road route (many points, isFallback=false) or the straight-
      // line fallback (2 points, isFallback=true). Visible in `flutter
      // run` console. Safe to leave in: dart:developer.log is debug-only.
      developer.log(
        'Directions result: points=${route.polyline.length} '
        'isFallback=${route.isFallback}',
        name: 'TripDetailModal',
      );
      if (!mounted || route.polyline.isEmpty) return;
      setState(() {
        _routeWarning = route.warningMessage;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('trip-route'),
            points: route.polyline,
            color: MyShopColors.primaryGold,
            width: 4,
          ),
        };
      });
    } catch (error, stack) {
      developer.log(
        'Directions fetch threw — staying on straight-line fallback',
        name: 'TripDetailModal',
        error: error,
        stackTrace: stack,
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Defer the bounds fit a tick so the map's render surface is sized
    // before we ask it to frame the camera — otherwise the padding maths
    // can overshoot on first frame and the pins clip out of view.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
  }

  void _fitBounds() {
    final controller = _mapController;
    if (controller == null) return;
    final south = math.min(widget.pickupLat, widget.dropoffLat);
    final north = math.max(widget.pickupLat, widget.dropoffLat);
    final west = math.min(widget.pickupLng, widget.dropoffLng);
    final east = math.max(widget.pickupLng, widget.dropoffLng);
    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final midLat = (widget.pickupLat + widget.dropoffLat) / 2;
    final midLng = (widget.pickupLng + widget.dropoffLng) / 2;
    return SizedBox(
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(midLat, midLng),
              zoom: 12,
            ),
            onMapCreated: _onMapCreated,
            markers: {
              Marker(
                markerId: const MarkerId('pickup'),
                position: LatLng(widget.pickupLat, widget.pickupLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueOrange),
                infoWindow: const InfoWindow(title: 'Pickup'),
              ),
              Marker(
                markerId: const MarkerId('dropoff'),
                position: LatLng(widget.dropoffLat, widget.dropoffLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed),
                infoWindow: const InfoWindow(title: 'Dropoff'),
              ),
            },
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            // Disable gestures so the modal scrolls cleanly past the map.
            zoomGesturesEnabled: false,
            scrollGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          ),
          // Bottom gradient fade for a cleaner edge against the content.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 48,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x33000000)],
                  ),
                ),
              ),
            ),
          ),
          // Distance badge (top right). Sits below the close button (8/8).
          Positioned(
            top: MyShopSpacing.md,
            right: MyShopSpacing.md + 32,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12171A1F),
                    blurRadius: 2.5,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation,
                      size: 12, color: MyShopColors.primaryGold),
                  const SizedBox(width: 4),
                  Text(
                    widget.distanceKm,
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.primaryGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_routeWarning case final warning?)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: RouteWarningBanner(message: warning),
            ),
        ],
      ),
    );
  }
}

/// Flat placeholder used when the ride has no coordinates to render a
/// real map for. Keeps the modal layout stable.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.distanceKm});
  final String distanceKm;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Center(
              child: Icon(Icons.map_outlined,
                  size: 48, color: MyShopColors.disabled),
            ),
          ),
          Positioned(
            top: MyShopSpacing.md,
            right: MyShopSpacing.md + 32,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation,
                      size: 12, color: MyShopColors.primaryGold),
                  const SizedBox(width: 4),
                  Text(
                    distanceKm,
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.primaryGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trip ID Tag ────────────────────────────────────────────────────────────

class _TripIdTag extends StatelessWidget {
  const _TripIdTag({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: MyShopColors.surfaceGrey),
      ),
      child: Center(
        child: Text(
          'TRIP-ID: #$tripId',
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: MyShopColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── Status Badge ───────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  bool get _isCompleted => status == 'Completed';

  @override
  Widget build(BuildContext context) {
    final bgColor =
        _isCompleted ? const Color(0xFFD1FAE5) : MyShopColors.errorLight;
    final textColor =
        _isCompleted ? const Color(0xFF047857) : MyShopColors.error;
    final icon = _isCompleted ? Icons.check_circle : Icons.cancel;

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Route Section (Pickup → Dropoff) ───────────────────────────────────────

class _RouteSection extends StatelessWidget {
  const _RouteSection({
    required this.pickupTime,
    required this.pickupAddress,
    required this.dropoffTime,
    required this.dropoffAddress,
  });

  final String pickupTime;
  final String pickupAddress;
  final String dropoffTime;
  final String dropoffAddress;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Route dots + line
        Column(
          children: [
            _RouteDot(color: MyShopColors.darkSlate),
            Container(width: 1, height: 52, color: MyShopColors.divider),
            _RouteDot(color: MyShopColors.primaryGold),
          ],
        ),
        const SizedBox(width: 16),

        // Addresses
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PICKUP · $pickupTime',
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                pickupAddress,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                  height: 1.36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'DROPOFF · $dropoffTime',
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dropoffAddress,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                  height: 1.36,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteDot extends StatelessWidget {
  const _RouteDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

// ─── Fare Breakdown Card ────────────────────────────────────────────────────

class _FareBreakdownCard extends StatelessWidget {
  const _FareBreakdownCard({required this.trip, required this.snapshot});
  final TripDetailData trip;

  /// Snapshot from `GET /rides/:id`. Null while the fetch is in flight
  /// (or if it failed). In that case the per-line values fall back to
  /// dashes; the headline Total Paid still comes from the list-endpoint
  /// value carried on [TripDetailData].
  final _RideSnapshot? snapshot;

  String _ghs(int pesewas) {
    final ghs = pesewas / 100;
    if (ghs == ghs.truncateToDouble() && ghs >= 1) {
      return 'GHS ${ghs.toStringAsFixed(0)}';
    }
    return 'GHS ${ghs.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final hasSnapshot = s != null;
    final baseFare = hasSnapshot ? _ghs(s.baseFarePesewas) : '—';
    final distanceFare = hasSnapshot ? _ghs(s.distanceFarePesewas) : '—';
    final bookingFee = hasSnapshot ? _ghs(s.bookingFeePesewas) : '—';
    final surge = hasSnapshot ? s.surgeMultiplier : 1.0;
    final showBookingFee = hasSnapshot && s.bookingFeePesewas > 0;
    final showSurge = surge > 1.0;

    // Total Paid: prefer the freshly-fetched total when available so a
    // late dispute adjustment is reflected; otherwise fall back to the
    // value already on the list row.
    final totalDisplay =
        hasSnapshot ? _ghs(s.totalFarePesewas) : trip.totalPaid;

    // Commission shown as 20% of total — the platform_config key is
    // `commission_rate_ride` and is fixed at 0.20 across the pilot.
    final totalPesewas = hasSnapshot ? s.totalFarePesewas : null;
    final commissionDisplay = totalPesewas != null
        ? _ghs((totalPesewas * 0.20).round())
        : trip.commission;

    return Container(
      margin: const EdgeInsets.fromLTRB(17, MyShopSpacing.md, 17, 0),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(
                bottom: BorderSide(color: MyShopColors.divider, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Fare Breakdown',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    letterSpacing: -0.35,
                  ),
                ),
                // Mirror the short user-facing identifier shown in the
                // top badge (`TRP-<8 hex>`). The full UUID lives on
                // `trip.rideId` for API calls only — never displayed.
                Text(
                  'ID: #${trip.tripId}',
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.primaryGold,
                    letterSpacing: -0.35,
                  ),
                ),
              ],
            ),
          ),

          // Line items
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
            child: Column(
              children: [
                _FareLine(label: 'Base Fare', amount: baseFare),
                const SizedBox(height: 16),
                _FareLine(
                    label: 'Distance (${trip.distanceKm})'
                        ' & Time (${trip.durationMins} mins)',
                    amount: distanceFare),
                if (showBookingFee) ...[
                  const SizedBox(height: 16),
                  _FareLine(label: 'Booking Fee', amount: bookingFee),
                ],
                if (showSurge) ...[
                  const SizedBox(height: 16),
                  _FareLine(
                    label: 'Surge Applied',
                    amount: '×${surge.toStringAsFixed(1)}',
                    icon: Icons.bolt,
                  ),
                ],

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: MyShopColors.divider),
                ),

                // Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Paid',
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    Text(
                      totalDisplay,
                      style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.darkSlate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Commission box
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MyShopColors.primaryGold),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 12, color: MyShopColors.textPrimary),
                          const SizedBox(width: 6),
                          const Text(
                            'Platform Commission (20%)',
                            style: TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: MyShopColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            commissionDisplay,
                            style: const TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: MyShopColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 22),
                        child: Text(
                          'Commission supports local artisan verification and 24/7 police-check monitoring.',
                          style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: MyShopColors.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Payment method footer
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border(
                top: BorderSide(color: MyShopColors.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.credit_card,
                    size: 16, color: MyShopColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  trip.paymentMethod,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                const Spacer(),
                const Text(
                  'SUCCESS',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders in place of [_FareBreakdownCard] when the ride wasn't completed.
/// A cancelled (or otherwise non-terminal) ride didn't collect fare from
/// the rider, so the breakdown / Total Paid / commission would be
/// misleading — we surface a single neutral notice instead.
class _CancelledFareNotice extends StatelessWidget {
  const _CancelledFareNotice({required this.status});

  /// Original status string from [TripDetailData], used in the message so
  /// the driver knows exactly which terminal state they're looking at.
  /// Falls back to "cancelled" if blank.
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = status.trim().isEmpty ? 'cancelled' : status.toLowerCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.errorLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 18,
              color: MyShopColors.error,
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No fare collected',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This ride was $label before completion, so no '
                    'payment was charged and no receipt is generated.',
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MyShopColors.textSecondary,
                      height: 1.4,
                    ),
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

class _FareLine extends StatelessWidget {
  const _FareLine({
    required this.label,
    required this.amount,
    this.icon,
  });

  final String label;
  final String amount;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon!, size: 14, color: MyShopColors.textSecondary),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        Text(
          amount,
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Ride snapshot ──────────────────────────────────────────────────────────

/// Parsed subset of the `GET /rides/:id` snapshot needed by the modal:
/// the pickup/dropoff coordinates (sourced from PostGIS via `ST_X`/`ST_Y`
/// in [RideSnapshotService], unavailable on the list endpoint) and the
/// per-line fare breakdown. The backend lumps the per-km and per-min
/// fare components into a single `distanceFare` bucket — we mirror that
/// shape here rather than inventing fields the API doesn't actually serve.
class _RideSnapshot {
  const _RideSnapshot({
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.baseFarePesewas,
    required this.distanceFarePesewas,
    required this.bookingFeePesewas,
    required this.totalFarePesewas,
    required this.surgeMultiplier,
  });

  factory _RideSnapshot.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    double asDouble(dynamic v, [double fallback = 0]) =>
        v is num ? v.toDouble() : fallback;
    return _RideSnapshot(
      pickupLat: asDouble(json['pickupLat']),
      pickupLng: asDouble(json['pickupLng']),
      dropoffLat: asDouble(json['dropoffLat']),
      dropoffLng: asDouble(json['dropoffLng']),
      baseFarePesewas: asInt(json['baseFare']),
      distanceFarePesewas: asInt(json['distanceFare']),
      bookingFeePesewas: asInt(json['bookingFee']),
      totalFarePesewas: asInt(json['totalFare']),
      surgeMultiplier: asDouble(json['surgeMultiplier'], 1.0),
    );
  }

  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final int baseFarePesewas;
  final int distanceFarePesewas;
  final int bookingFeePesewas;
  final int totalFarePesewas;
  final double surgeMultiplier;
}

// ─── Data Model ─────────────────────────────────────────────────────────────

/// Data needed to display the trip detail modal.
class TripDetailData {
  const TripDetailData({
    required this.tripId,
    required this.rideId,
    required this.status,
    required this.date,
    required this.timeRange,
    required this.pickupTime,
    required this.pickupAddress,
    required this.dropoffTime,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.durationMins,
    required this.surgeMultiplier,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.surgeFare,
    required this.subtotal,
    required this.taxes,
    required this.promoDiscount,
    required this.totalPaid,
    required this.commission,
    required this.paymentMethod,
  });

  final String tripId;
  final String rideId;
  final String status;
  final String date;
  final String timeRange;
  final String pickupTime;
  final String pickupAddress;
  final String dropoffTime;
  final String dropoffAddress;
  final String distanceKm;
  final int durationMins;
  final String surgeMultiplier;
  final String baseFare;
  final String distanceFare;
  final String timeFare;
  final String surgeFare;
  final String subtotal;
  final String taxes;
  final String promoDiscount;
  final String totalPaid;
  final String commission;
  final String paymentMethod;
}
