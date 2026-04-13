import 'package:flutter/material.dart';

import '../providers/ride_provider.dart';
import '../widgets/driver_profile_header.dart';
import '../widgets/fare_breakdown_card.dart';
import '../widgets/ride_safety_banner.dart';
import '../widgets/vehicle_details_card.dart';
import 'ride_tracking_screen.dart';

// Design tokens
const _offWhite = Color(0xFFF6F7F8);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _success = Color(0xFF27AE60);
const _error = Color(0xFFEB5757);
const _divider = Color(0xFFE0E0E0);

/// PRD 4.3 — Driver Found / Acceptance Screen
/// Shows full driver profile, vehicle details, fare breakdown,
/// safety tip, and confirm / cancel actions.
class DriverFoundScreen extends StatelessWidget {
  final MatchedDriver driver;

  const DriverFoundScreen({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _offWhite,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Profile hero ────────────────────────────────────────
                  ColoredBox(
                    color: Colors.white,
                    child: Column(
                      children: [
                        DriverProfileHeader(driver: driver),
                        const Divider(
                            height: 1, thickness: 1, color: _divider),
                      ],
                    ),
                  ),
                  // ── Trip details ────────────────────────────────────────
                  _TripDetailsSection(driver: driver),
                ],
              ),
            ),
          ),
          // ── Sticky bottom actions ───────────────────────────────────────
          _BottomActions(
            onConfirm: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => RideTrackingScreen(
                  driver: driver,
                  destination: 'Kumasi City Mall, Lake Road',
                ),
              ),
            ),
            onCancel: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded, color: _textPrimary),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Driver Found',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _success,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'ACTIVE SEARCH',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Trip details section ──────────────────────────────────────────────────────

class _TripDetailsSection extends StatelessWidget {
  final MatchedDriver driver;
  const _TripDetailsSection({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(text: 'TRIP DETAILS'),
          const SizedBox(height: 12),
          VehicleDetailsCard(driver: driver),
          const SizedBox(height: 2),
          FareBreakdownCard(driver: driver),
          const SizedBox(height: 14),
          RideSafetyBanner(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: _textSecondary,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ── Bottom actions ────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _BottomActions({required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF161A1D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Confirm Ride',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onCancel,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cancel_outlined,
                  size: 16,
                  color: _error,
                ),
                const SizedBox(width: 6),
                Text(
                  'Cancel Request',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Free cancellation within 3 minutes of match.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: _textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
