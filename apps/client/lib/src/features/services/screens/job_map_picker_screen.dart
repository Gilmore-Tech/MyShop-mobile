import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/di/providers.dart';
import '../providers/job_form_provider.dart';

/// Full-screen Google Map with a center crosshair for pin-dropping.
/// The user moves the map; on "Confirm" we reverse-geocode the center
/// and write the location back to the job form.
class JobMapPickerScreen extends ConsumerStatefulWidget {
  const JobMapPickerScreen({super.key});

  @override
  ConsumerState<JobMapPickerScreen> createState() =>
      _JobMapPickerScreenState();
}

class _JobMapPickerScreenState extends ConsumerState<JobMapPickerScreen> {
  GoogleMapController? _mapController;

  /// Default center: Kumasi, Ashanti Region.
  static const _defaultCenter = LatLng(6.6885, -1.6244);

  LatLng _currentCenter = _defaultCenter;
  String _address = '';
  bool _isGeocoding = false;

  @override
  void initState() {
    super.initState();
    // If the form already has coordinates, start there.
    final state = ref.read(jobFormProvider);
    if (state.latitude != null && state.longitude != null) {
      _currentCenter = LatLng(state.latitude!, state.longitude!);
    }
  }

  void _onCameraIdle() {
    _reverseGeocode(_currentCenter);
  }

  void _onCameraMove(CameraPosition position) {
    _currentCenter = position.target;
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
    ref.read(jobFormProvider.notifier).setLocation(
          address: _address,
          latitude: _currentCenter.latitude,
          longitude: _currentCenter.longitude,
        );
    // Pop both map picker and search screen back to the form.
    if (context.canPop()) context.pop();
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: [
          // ── Google Map ────────────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentCenter,
                zoom: 15,
              ),
              onMapCreated: (controller) => _mapController = controller,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Center crosshair pin ──────────────────────────────────────────
          const _CenterPin(),

          // ── Top bar ───────────────────────────────────────────────────────
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
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
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
                      child: const Text(
                        'Choose job location',
                        style: TextStyle(
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

          // ── My location FAB ──────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 200 + bottomPad,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                onPressed: () {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(_defaultCenter),
                  );
                },
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ),
          ),

          // ── Bottom confirmation sheet ─────────────────────────────────────
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
                      const Icon(
                        Icons.place_rounded,
                        color: MyShopColors.darkSlate,
                        size: 20,
                      ),
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
                      child: const Text(
                        'Confirm location',
                        style: TextStyle(
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

// ── Center pin overlay ─────────────────────────────────────────────────────

class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Padding(
          // Offset upwards so the pin tip is at center.
          padding: const EdgeInsets.only(bottom: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on,
                color: MyShopColors.primaryGold,
                size: 44,
              ),
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
