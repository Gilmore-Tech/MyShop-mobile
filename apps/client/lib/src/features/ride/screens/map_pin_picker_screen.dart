import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/edit_trip_provider.dart';
import '../providers/ride_search_provider.dart';
import 'destination_search_screen.dart' show kNewStopSentinel;

/// Full-screen map pin picker. A crosshair at screen center lets the user
/// drop a pin; "Confirm" writes the location back to ride-search state and
/// pops the screen.
///
/// NOTE: the map itself is a placeholder — swap `_MapPlaceholder` with the
/// Google Maps SDK widget once the key is wired.
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
  // Mock "reverse-geocoded" address. Real impl will call Google Geocoding API
  // every time the camera stops moving (and flip this to non-final).
  final String _address = 'Kumasi Central Market, Adum';

  bool get _isPickup => widget.field == RideSearchField.pickup;
  bool get _isStopEdit => widget.stopId != null;

  void _confirm() {
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
            ),
          );
    }
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Stack(
        children: [
          const Positioned.fill(child: _MapPlaceholder()),
          const _CenterCrosshair(),
          _TopBar(
            title: _isPickup ? 'Choose pickup' : 'Choose destination',
            onBack: () => context.pop(),
          ),
          _BottomSheet(
            address: _address,
            ctaLabel: _isPickup ? 'Confirm pickup' : 'Confirm destination',
            onConfirm: _confirm,
          ),
        ],
      ),
    );
  }
}

// ── Placeholder "map" — swap for GoogleMap when SDK is wired ─────────────────

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE5EAEE),
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Center crosshair pin ─────────────────────────────────────────────────────

class _CenterCrosshair extends StatelessWidget {
  const _CenterCrosshair();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: MyShopColors.primaryGold, size: 44),
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
    );
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, top + 8, 12, 8),
        child: Row(
          children: [
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: MyShopColors.textPrimary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  title,
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
    );
  }
}

// ── Bottom confirmation sheet ────────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  final String address;
  final String ctaLabel;
  final VoidCallback onConfirm;

  const _BottomSheet({
    required this.address,
    required this.ctaLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                const Icon(Icons.place_rounded, color: MyShopColors.darkSlate, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address,
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
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.primaryGold,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  ctaLabel,
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
    );
  }
}
