import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';
import '../providers/ride_search_provider.dart';
import '../widgets/payment_method_row.dart';
import '../widgets/pickup_destination_fields.dart';
import '../widgets/recent_destination_card.dart';
import '../widgets/surge_pricing_banner.dart';
import '../widgets/vehicle_option_card.dart';

/// PRD 4.3 — Plan Your Trip
///
/// Vehicle selection, surge banner, payment, and the confirm CTA only appear
/// once both pickup and destination are set — EDD POST /v1/rides/estimate
/// requires both endpoints before the backend can return ride categories.
class FareEstimateScreen extends ConsumerWidget {
  const FareEstimateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(rideSearchProvider);
    final hasPickup = search.pickup != null;
    final hasDestination = search.destination != null;
    final ready = hasPickup && hasDestination;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PickupDestinationFields(
                      pickupLabel: search.pickup?.name ?? 'Choose pickup',
                      destinationLabel: search.destination?.name,
                      onPickupTap: () => context
                          .push(AppRoutes.rideSearchPath('pickup')),
                      onDestinationTap: () => context
                          .push(AppRoutes.rideSearchPath('destination')),
                      onDestinationPinTap: () => context
                          .push(AppRoutes.ridePinPickerPath('destination')),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _RecentDestinationsSection(
                    onSelect: (d) => ref
                        .read(rideSearchProvider.notifier)
                        .setLocation(
                          RideSearchField.destination,
                          RideLocation(name: d.label, address: d.address),
                        ),
                  ),
                  if (ready) ...[
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SurgePricingBanner(),
                    ),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _VehicleSelectionSection(),
                    ),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(color: MyShopColors.divider),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: _PaymentSection(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          if (ready) _BottomActions(onConfirm: () => _onConfirmRide(context)),
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
        icon: const Icon(Icons.arrow_back_rounded, color: MyShopColors.textPrimary),
      ),
      title: const Text(
        'Plan Your Trip',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
        ),
      ),
    );
  }

  void _onConfirmRide(BuildContext context) {
    context.go(AppRoutes.rideMatching);
  }
}

// ── Sections ──────────────────────────────────────────────────────────────────

class _RecentDestinationsSection extends StatelessWidget {
  final ValueChanged<RecentDestination> onSelect;

  const _RecentDestinationsSection({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Fixed card width so cards stay compact and the 3rd peeks past the edge.
    const cardWidth = 150.0;
    const cardHeight = 72.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _SectionHeader(
              title: 'RECENT DESTINATIONS', actionLabel: 'View All'),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recentDestinations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: cardWidth,
              child: RecentDestinationCard(
                destination: recentDestinations[i],
                onTap: () => onSelect(recentDestinations[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VehicleSelectionSection extends ConsumerWidget {
  const _VehicleSelectionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              'Select Vehicle',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            Text(
              'View All',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MyShopColors.primaryGold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
  const _PaymentSection();

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
            color: MyShopColors.textSecondary,
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
                backgroundColor: MyShopColors.darkSlate,
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
            onTap: () => context.pop(),
            child: const Text(
              'Cancel Request',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Free cancellation within 3 minutes of match',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
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
            color: MyShopColors.textSecondary,
            letterSpacing: 1.4,
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MyShopColors.primaryGold,
            ),
          ),
      ],
    );
  }
}
