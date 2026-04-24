import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/di/providers.dart';
import '../providers/edit_trip_provider.dart';
import '../providers/ride_search_provider.dart';
import 'destination_search_screen.dart' show kNewStopSentinel;

/// Full-screen Google Map pin picker. A crosshair at screen center lets the
/// user drop a pin; "Confirm" reverse-geocodes the address and writes the
/// location back to ride-search state, then pops.
class MapPinPickerScreen extends ConsumerStatefulWidget {
  final RideSearchField field;

  /// When non-null we're picking a location for a trip stop (Edit Your Trip
  /// flow) rather than the pickup/destination on the fare-estimate flow.
  /// Pass [kNewStopSentinel] to create a new intermediate stop.
  final String? stopId;

  const MapPinPickerScreen({
    super.key,
    required this.field,
    this.stopId,
  });

  @override
  ConsumerState<MapPinPickerScreen> createState() => _MapPinPickerScreenState();
}

class _MapPinPickerScreenState extends ConsumerState<MapPinPickerScreen> {
  GoogleMapController? _mapController;

  /// Default center: Kumasi, Ashanti Region.
  static const _defaultCenter = LatLng(6.6885, -1.6244);

  LatLng _currentCenter = _defaultCenter;
  String _address = '';
  bool _isGeocoding = false;
  bool _centerOnUserOnMapReady = false;

  bool get _isPickup => widget.field == RideSearchField.pickup;
  bool get _isStopEdit => widget.stopId != null;

  @override
  void initState() {
    super.initState();
    final searchState = ref.read(rideSearchProvider);
    final existing = _isPickup ? searchState.pickup : searchState.destination;
    if (existing?.lat != null && existing?.lng != null) {
      _currentCenter = LatLng(existing!.lat!, existing.lng!);
    } else {
      // No prior location — will move to GPS once the map controller is ready.
      _centerOnUserOnMapReady = true;
    }
  }

  Future<void> _goToMyLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    if (!mounted) return;

    final target = LatLng(position.latitude, position.longitude);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
  }

  void _onCameraMove(CameraPosition position) {
    _currentCenter = position.target;
  }

  void _onCameraIdle() {
    _reverseGeocode(_currentCenter);
  }

  Future<void> _reverseGeocode(LatLng position) async {
    setState(() => _isGeocoding = true);
    final places = ref.read(googlePlacesServiceProvider);
    final result = await places.reverseGeocode(
      position.latitude,
      position.longitude,
    );
    if (!mounted) return;
    setState(() {
      _address = result ?? 'Unknown location';
      _isGeocoding = false;
    });
  }

  void _confirm() {
    if (_address.isEmpty || _isGeocoding) return;

    if (_isStopEdit) {
      final stops = ref.read(tripStopsProvider.notifier);
      if (widget.stopId == kNewStopSentinel) {
        stops.addIntermediateStop(_address);
      } else {
        stops.updateStopAddress(widget.stopId!, _address);
      }
    } else {
      ref.read(rideSearchProvider.notifier).setLocation(
            widget.field,
            RideLocation(
              name: _address.split(',').first.trim(),
              address: _address,
              lat: _currentCenter.latitude,
              lng: _currentCenter.longitude,
            ),
          );
    }
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Stack(
        children: [
          // ── Google Map ──────────────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentCenter,
                zoom: 15,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_centerOnUserOnMapReady) _goToMyLocation();
              },
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Center crosshair pin ───────────────────────────────────────────
          const _CenterCrosshair(),

          // ── Top bar ────────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, topPad + 8, 12, 8),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: MyShopColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _isPickup ? 'Choose pickup' : 'Choose destination',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── My location FAB ────────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 200 + bottomPad,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                onPressed: _goToMyLocation,
                icon: const Icon(Icons.my_location_rounded,
                    color: MyShopColors.textPrimary),
              ),
            ),
          ),

          // ── Bottom confirmation sheet ──────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SELECTED LOCATION',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textSecondary,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          color: MyShopColors.darkSlate, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _isGeocoding
                            ? Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: MyShopColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Finding address...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: MyShopColors.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                _address.isEmpty
                                    ? 'Move the map to select'
                                    : _address,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: MyShopColors.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          _address.isNotEmpty && !_isGeocoding
                              ? _confirm
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyShopColors.primaryGold,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: MyShopColors.surfaceGrey,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _isPickup ? 'Confirm pickup' : 'Confirm destination',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

// ── Center crosshair pin ─────────────────────────────────────────────────────

class _CenterCrosshair extends StatelessWidget {
  const _CenterCrosshair();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on,
                  color: MyShopColors.primaryGold, size: 44),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
