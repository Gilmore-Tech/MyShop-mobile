import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../home/providers/home_provider.dart';
import '../data/ride_cancellation_coordinator.dart';
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
class DriverFoundScreen extends ConsumerWidget {
  final MatchedDriver driver;

  const DriverFoundScreen({super.key, required this.driver});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onCancel: () => _confirmAndCancelRide(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndCancelRide(
      BuildContext context, WidgetRef ref) async {
    final rideId = ref.read(activeRideIdProvider);
    if (rideId == null || rideId.isEmpty) {
      context.go(AppRoutes.home);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text(
          'Are you sure you want to cancel this ride?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final cancellation = await cancelRideWithAuthority(
      rideService: ref.read(rideServiceProvider),
      rideId: rideId,
      reason: 'rider_cancelled',
    );
    if (!cancellation.confirmedCancelled) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(cancellation.message)));
      }
      return;
    }

    await ref.read(rideBookingAttemptStoreProvider).clear();
    ref.invalidate(homeRecentActivityProvider);
    final result = cancellation.response;
    final feePesewas = (result['cancellationFeePesewas'] as num?)?.toInt() ?? 0;
    var message = cancellation.message;
    if (result['cancellationConsequencesApplied'] == false) {
      message = result['notice'] as String? ??
          'Ride cancelled. Automatic fees and penalties are temporarily paused.';
    } else if (feePesewas > 0) {
      final fee = (feePesewas / 100).toStringAsFixed(2);
      message = 'Ride cancelled. Cancellation fee: GHS $fee';
    }

    // Never hide an active backend ride after a failed or ambiguous request.
    ref.read(activeRideIdProvider.notifier).state = null;
    ref.read(activeRideRouteUpdateProvider.notifier).state = null;
    ref.read(matchedDriverProvider.notifier).state = null;
    ref.read(bookingPhaseProvider.notifier).reset();

    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
    context.go(AppRoutes.home);
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
        ],
      ),
    );
  }
}
