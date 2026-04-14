import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/ride_provider.dart';
import '../widgets/ride_route_map.dart';
import '../widgets/ride_tracking_sheet.dart';

// Design tokens
const _error = Color(0xFFEB5757);

/// PRD 4.6 — Ride Tracking Screen
/// Live route map with ETA pill, driver info sheet, chat/share actions, SOS FAB.
class RideTrackingScreen extends ConsumerStatefulWidget {
  final MatchedDriver driver;
  final String destination;

  const RideTrackingScreen({
    super.key,
    required this.driver,
    this.destination = 'Kumasi City Mall, Lake Road',
  });

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen> {
  Timer? _etaTimer;

  @override
  void initState() {
    super.initState();
    ref.read(rideEtaProvider.notifier).setEta(4);
    // Tick ETA down every 60s — use shorter interval in dev for visibility
    _etaTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.read(rideEtaProvider.notifier).decrement();
    });
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eta = ref.watch(rideEtaProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFEDEDE6),
      body: Stack(
        children: [
          // ── Full screen: map (top) + bottom sheet (bottom) ─────────────
          Column(
            children: [
              Expanded(
                child: RideRouteMap(
                  destination: widget.destination,
                  etaMinutes: eta,
                  onBack: () => context.pop(),
                ),
              ),
              RideTrackingSheet(driver: widget.driver),
            ],
          ),
          // ── SOS FAB — positioned over the sheet, bottom-right ──────────
          Positioned(
            right: 16,
            bottom: _kSheetEstimatedHeight + 12,
            child: const _SosButton(),
          ),
        ],
      ),
    );
  }
}

// Approximate height of the bottom sheet for SOS button positioning.
// Adjust if the sheet content changes significantly.
const double _kSheetEstimatedHeight = 280;

// ── SOS button ────────────────────────────────────────────────────────────────

class _SosButton extends StatelessWidget {
  const _SosButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSosDialog(context),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _error,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _error.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'SOS',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  void _showSosDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Emergency',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF161A1D),
          ),
        ),
        content: const Text(
          'Are you in danger? We will call Ghana Police Service (191) and share your location.',
          style: TextStyle(color: Color(0xFF555E68)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF555E68)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: url_launcher → tel:191 + send location to backend
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Call 191'),
          ),
        ],
      ),
    );
  }
}
