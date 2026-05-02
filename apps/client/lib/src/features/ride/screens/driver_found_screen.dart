import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';
import '../widgets/driver_profile_header.dart';
import '../widgets/fare_breakdown_card.dart';
import '../widgets/ride_safety_banner.dart';
import '../widgets/vehicle_details_card.dart';

/// PRD 4.3 — Driver Details Screen
///
/// Reached from the tracking screen (tap the driver row in the bottom sheet).
/// Shows full driver profile, vehicle details, fare breakdown, and a cancel
/// request action. Back arrow returns to the map.
class DriverFoundScreen extends StatelessWidget {
  final MatchedDriver driver;

  const DriverFoundScreen({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DriverProfileHeader(driver: driver),
                  const SizedBox(height: 20),
                  const _SectionLabel(text: 'TRIP DETAILS'),
                  const SizedBox(height: 12),
                  VehicleDetailsCard(driver: driver),
                  const SizedBox(height: 12),
                  FareBreakdownCard(driver: driver),
                  const SizedBox(height: 14),
                  const RideSafetyBanner(),
                ],
              ),
            ),
          ),
          _BottomActions(
            onCancel: () => context.go(AppRoutes.home),
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
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_rounded,
            color: MyShopColors.textPrimary),
      ),
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Driver Details',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
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
                  color: MyShopColors.success,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'TRIP IN PROGRESS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
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

// ── Section label ────────────────────────────────────────────────────────────

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
        color: MyShopColors.textSecondary,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ── Bottom actions ────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final VoidCallback onCancel;

  const _BottomActions({required this.onCancel});

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
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.error,
                side: BorderSide(
                    color: MyShopColors.error.withValues(alpha: 0.5),
                    width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.cancel_outlined,
                  size: 18, color: MyShopColors.error),
              label: const Text(
                'Cancel Request',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Free cancellation within 3 minutes of match.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
