import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';
import '../widgets/payment_method_row.dart';
import '../widgets/pickup_destination_fields.dart';
import '../widgets/recent_destination_card.dart';
import '../widgets/surge_pricing_banner.dart';
import '../widgets/vehicle_option_card.dart';

// Design tokens
const _offWhite = Color(0xFFF6F7F8);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold = Color(0xFFF5A623);
const _divider = Color(0xFFE0E0E0);

/// PRD 4.3 — Plan Your Trip
/// Pickup + destination entry, vehicle selection, fare display, payment method, confirm CTA.
class FareEstimateScreen extends ConsumerStatefulWidget {
  const FareEstimateScreen({super.key});

  @override
  ConsumerState<FareEstimateScreen> createState() => _FareEstimateScreenState();
}

class _FareEstimateScreenState extends ConsumerState<FareEstimateScreen> {
  final _destinationController = TextEditingController();

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _offWhite,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PickupDestinationFields(
                    pickupLocation: 'Kejetia Market, Kumasi',
                    destinationController: _destinationController,
                  ),
                  const SizedBox(height: 20),
                  _RecentDestinationsSection(),
                  const SizedBox(height: 16),
                  const SurgePricingBanner(),
                  const SizedBox(height: 20),
                  _VehicleSelectionSection(),
                  const SizedBox(height: 16),
                  const Divider(color: _divider),
                  const SizedBox(height: 10),
                  _PaymentSection(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _BottomActions(onConfirm: _onConfirmRide),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_rounded, color: _textPrimary),
      ),
      title: const Text(
        'Plan Your Trip',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _textPrimary,
        ),
      ),
    );
  }

  void _onConfirmRide() {
    context.go(AppRoutes.rideMatching);
  }
}

// ── Sections ──────────────────────────────────────────────────────────────────

class _RecentDestinationsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(title: 'RECENT DESTINATIONS', actionLabel: 'View All'),
        const SizedBox(height: 10),
        Row(
          children: recentDestinations
              .map(
                (d) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: d == recentDestinations.last ? 0 : 10,
                    ),
                    child: RecentDestinationCard(destination: d),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _VehicleSelectionSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(title: 'Select Vehicle', actionLabel: 'View All'),
        const SizedBox(height: 10),
        ...vehicleOptions.map(
          (v) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: VehicleOptionCard(
              option: v,
              isSelected: selectedId == v.id,
              onTap: () =>
                  ref.read(selectedVehicleProvider.notifier).state = v.id,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'PAYMENT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: _textSecondary,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        PaymentMethodRow(onChangeTap: () {}),
      ],
    );
  }
}

// ── Bottom actions ────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final VoidCallback onConfirm;
  const _BottomActions({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel Request',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Free cancellation within 3 minutes of match',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared section header ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;

  const _SectionHeader({required this.title, this.actionLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: _textSecondary,
            letterSpacing: 1.4,
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _gold,
            ),
          ),
      ],
    );
  }
}
