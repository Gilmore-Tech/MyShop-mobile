import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../services/directions_service.dart';

/// A compact, non-interactive map used on authenticated incoming-request
/// screens.
///
/// The widget paints the useful decision context immediately: a job location,
/// or a straight pickup-to-destination line for a ride. Ride previews then
/// replace that line with the authenticated backend road route when it arrives.
/// A route lookup never blocks the request card or extends its countdown.
class IncomingRequestMapPreview extends ConsumerStatefulWidget {
  IncomingRequestMapPreview.route({
    super.key,
    required double pickupLatitude,
    required double pickupLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    this.height = 168,
  })  : origin = LatLng(pickupLatitude, pickupLongitude),
        destination = LatLng(destinationLatitude, destinationLongitude),
        semanticsLabel = 'Map preview showing pickup and destination';

  IncomingRequestMapPreview.location({
    super.key,
    required double latitude,
    required double longitude,
    this.height = 160,
  })  : origin = LatLng(latitude, longitude),
        destination = null,
        semanticsLabel = 'Map preview showing the job location';

  final LatLng origin;
  final LatLng? destination;
  final double height;
  final String semanticsLabel;

  bool get showsRoute => destination != null;

  /// Backend models use `(0, 0)` as the defensive default for missing
  /// coordinates. Treat that pair as unavailable rather than showing a pin in
  /// the Gulf of Guinea or printing raw coordinates in a fallback message.
  static bool isUsableCoordinate(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    return latitude.abs() > 0.000001 || longitude.abs() > 0.000001;
  }

  @visibleForTesting
  static LatLngBounds? boundsFor(LatLng first, LatLng? second) {
    if (second == null || first == second) return null;
    return LatLngBounds(
      southwest: LatLng(
        math.min(first.latitude, second.latitude),
        math.min(first.longitude, second.longitude),
      ),
      northeast: LatLng(
        math.max(first.latitude, second.latitude),
        math.max(first.longitude, second.longitude),
      ),
    );
  }

  @override
  ConsumerState<IncomingRequestMapPreview> createState() =>
      _IncomingRequestMapPreviewState();
}

class _IncomingRequestMapPreviewState
    extends ConsumerState<IncomingRequestMapPreview> {
  GoogleMapController? _controller;
  late List<LatLng> _routePoints;
  bool _loadingRoadRoute = false;
  bool _usingApproximateRoute = false;
  int _routeGeneration = 0;

  bool get _hasValidOrigin => IncomingRequestMapPreview.isUsableCoordinate(
        widget.origin.latitude,
        widget.origin.longitude,
      );

  bool get _hasValidDestination {
    final destination = widget.destination;
    return destination == null ||
        IncomingRequestMapPreview.isUsableCoordinate(
          destination.latitude,
          destination.longitude,
        );
  }

  bool get _hasUsableLocation => _hasValidOrigin && _hasValidDestination;

  @override
  void initState() {
    super.initState();
    _resetRoute();
  }

  @override
  void didUpdateWidget(covariant IncomingRequestMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.origin != widget.origin ||
        oldWidget.destination != widget.destination) {
      _resetRoute();
      unawaited(_fitCamera());
    }
  }

  void _resetRoute() {
    _routeGeneration += 1;
    _routePoints = widget.destination == null
        ? const <LatLng>[]
        : <LatLng>[widget.origin, widget.destination!];
    _loadingRoadRoute = widget.showsRoute && _hasUsableLocation;
    _usingApproximateRoute = false;
    if (_loadingRoadRoute) {
      final generation = _routeGeneration;
      scheduleMicrotask(() {
        if (!mounted || generation != _routeGeneration) return;
        unawaited(_loadRoadRoute(generation));
      });
    }
  }

  Future<void> _loadRoadRoute(int generation) async {
    final destination = widget.destination;
    if (destination == null || !_hasUsableLocation) return;

    final route = await ref.read(directionsServiceProvider).fetchRoute(
          origin: widget.origin,
          destination: destination,
        );
    if (!mounted || generation != _routeGeneration) return;

    setState(() {
      _routePoints = route.polyline.length >= 2
          ? route.polyline
          : <LatLng>[widget.origin, destination];
      _loadingRoadRoute = false;
      _usingApproximateRoute = route.isFallback;
    });
    await _fitCamera();
  }

  Future<void> _fitCamera() async {
    final controller = _controller;
    if (controller == null || !_hasUsableLocation) return;
    final bounds = IncomingRequestMapPreview.boundsFor(
      widget.origin,
      widget.destination,
    );
    try {
      if (bounds == null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(widget.origin, 15),
        );
      } else {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 44),
        );
      }
    } catch (_) {
      // A platform map can reject a bounds update during its first layout.
      // The initial camera already frames the request, so this is cosmetic.
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_fitCamera());
    });
  }

  @override
  void dispose() {
    _routeGeneration += 1;
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUsableLocation) {
      return _UnavailableMapPreview(height: widget.height);
    }

    final destination = widget.destination;
    final markers = <Marker>{
      Marker(
        markerId: MarkerId(destination == null ? 'job-location' : 'pickup'),
        position: widget.origin,
        infoWindow: InfoWindow(
          title: destination == null ? 'Job location' : 'Pickup',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueOrange,
        ),
      ),
      if (destination != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          infoWindow: const InfoWindow(title: 'Destination'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };
    final polylines = destination == null
        ? const <Polyline>{}
        : <Polyline>{
            Polyline(
              polylineId: const PolylineId('request-route'),
              points: _routePoints,
              color: _usingApproximateRoute
                  ? MyShopColors.textSecondary
                  : MyShopColors.darkSlate,
              width: 5,
            ),
          };

    return Semantics(
      container: true,
      image: true,
      label: widget.semanticsLabel,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(MyShopRadius.card),
          border: Border.all(color: MyShopColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _initialTarget(widget.origin, destination),
                  zoom: destination == null ? 15 : 12,
                ),
                onMapCreated: _onMapCreated,
                markers: markers,
                polylines: polylines,
                mapType: MapType.normal,
                liteModeEnabled:
                    defaultTargetPlatform == TargetPlatform.android,
                compassEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                myLocationEnabled: false,
                rotateGesturesEnabled: false,
                scrollGesturesEnabled: false,
                tiltGesturesEnabled: false,
                zoomControlsEnabled: false,
                zoomGesturesEnabled: false,
              ),
            ),
            Positioned(
              left: MyShopSpacing.sm,
              top: MyShopSpacing.sm,
              child: _MapStatusPill(
                icon: destination == null
                    ? Icons.location_on_outlined
                    : Icons.alt_route,
                label: destination == null
                    ? 'Job location'
                    : _loadingRoadRoute
                        ? 'Loading road route…'
                        : _usingApproximateRoute
                            ? 'Approximate route'
                            : 'Route preview',
              ),
            ),
          ],
        ),
      ),
    );
  }

  LatLng _initialTarget(LatLng origin, LatLng? destination) {
    if (destination == null) return origin;
    return LatLng(
      (origin.latitude + destination.latitude) / 2,
      (origin.longitude + destination.longitude) / 2,
    );
  }
}

class _MapStatusPill extends StatelessWidget {
  const _MapStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(MyShopRadius.pill),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 8),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.sm,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: MyShopColors.darkSlate),
            const SizedBox(width: MyShopSpacing.xs),
            Text(
              label,
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableMapPreview extends StatelessWidget {
  const _UnavailableMapPreview({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Map preview unavailable',
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(MyShopRadius.card),
          border: Border.all(color: MyShopColors.divider),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(MyShopSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.map_outlined,
              size: 32,
              color: MyShopColors.textSecondary,
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              'Map preview unavailable',
              style: MyShopTypography.body1.copyWith(
                color: MyShopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
