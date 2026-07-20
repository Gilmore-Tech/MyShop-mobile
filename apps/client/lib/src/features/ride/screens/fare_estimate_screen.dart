import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/fare_estimate_provider.dart';
import '../providers/edit_trip_provider.dart';
import '../providers/ride_payment_method_provider.dart';
import '../providers/ride_provider.dart';
import '../providers/ride_search_provider.dart';
import 'destination_search_screen.dart' show kNewStopSentinel;
import '../utils/ride_error_messages.dart';
import '../widgets/payment_method_row.dart';
import '../widgets/pickup_destination_fields.dart';
import '../widgets/recent_destination_card.dart';
import '../widgets/route_stop_list.dart';
import '../widgets/surge_pricing_banner.dart';
import '../widgets/vehicle_option_card.dart';

/// PRD 4.3 — Plan Your Trip
///
/// Vehicle selection, surge banner, payment, and the confirm CTA only appear
/// once both pickup and destination are set — EDD POST /v1/rides/estimate
/// requires both endpoints before the backend can return ride categories.
class FareEstimateScreen extends ConsumerWidget {
  const FareEstimateScreen({super.key});

  /// Clear sticky trip state when the user abandons the screen. Called on
  /// both the back arrow and the Cancel button — without it, the next
  /// visit shows the previous pickup + destination + vehicle, which the
  /// user reads as "the app remembered a trip I already cancelled".
  void _resetTripState(WidgetRef ref) {
    ref.read(rideSearchProvider.notifier).reset();
    ref.read(tripStopsProvider.notifier).clear();
    ref.read(selectedVehicleProvider.notifier).state = '';
  }

  void _seedPreTripStops(WidgetRef ref, RideSearchState search) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tripStopsProvider.notifier).seedPreTrip(
        pickup: (
          address: search.pickup?.address ?? search.pickup?.name,
          lat: search.pickup?.lat,
          lng: search.pickup?.lng,
        ),
        destination: (
          address: search.destination?.address ?? search.destination?.name,
          lat: search.destination?.lat,
          lng: search.destination?.lng,
        ),
      );
    });
  }

  List<Map<String, dynamic>> _bookingStops(
    WidgetRef ref,
    bool multistopEnabled,
  ) {
    if (!multistopEnabled) return const [];
    return ref
        .read(tripStopsProvider)
        .where((s) =>
            s.type == StopType.intermediate && s.lat != null && s.lng != null)
        .map(
          (s) => {
            'lat': s.lat!,
            'lng': s.lng!,
            if (s.address.trim().isNotEmpty) 'addressText': s.address.trim(),
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(rideSearchProvider);
    final hasPickup = search.pickup != null;
    final hasDestination = search.destination != null;
    final needsExactPoint =
        (search.pickup != null && !search.pickup!.isPrecise) ||
            (search.destination != null && !search.destination!.isPrecise);
    final hasCoords = search.pickup?.lat != null &&
        search.destination?.lat != null &&
        !needsExactPoint;
    final multistopEnabled =
        ref.watch(pretripMultistopEnabledProvider).valueOrNull ?? false;
    if (hasCoords && multistopEnabled) {
      _seedPreTripStops(ref, search);
    }
    final estimate = ref.watch(fareEstimateProvider);
    final options = estimate.valueOrNull;
    final estimateReady = options?.isNotEmpty == true;
    // The fare on the currently-selected vehicle is what the client will pay —
    // surface it boldly in the confirm bar so it's the clearest number on the
    // screen before they commit.
    final selectedId = ref.watch(selectedVehicleProvider);
    final selectedOption =
        estimateReady ? availableRideOptionById(options!, selectedId) : null;

    return PopScope(
      canPop: true,
      // Fires AFTER the pop has happened, so the screen is already off
      // screen. Resetting here makes the Android back-gesture / iOS
      // edge-swipe match the explicit Cancel / back-arrow behaviour —
      // every exit path leaves the trip state clean for the next entry.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _resetTripState(ref);
      },
      child: Scaffold(
        backgroundColor: MyShopColors.offWhite,
        appBar: _buildAppBar(context, ref),
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
                        onPickupTap: () =>
                            context.push(AppRoutes.rideSearchPath('pickup')),
                        onDestinationTap: () => context
                            .push(AppRoutes.rideSearchPath('destination')),
                        onDestinationPinTap: () => context
                            .push(AppRoutes.ridePinPickerPath('destination')),
                      ),
                    ),
                    if (needsExactPoint) ...[
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: _ExactPointNotice(),
                      ),
                    ],
                    if (hasCoords && multistopEnabled) ...[
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: _PreTripStopsSection(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (!hasPickup || !hasDestination)
                      _RecentDestinationsSection(
                        onSelect: (d) => ref
                            .read(rideSearchProvider.notifier)
                            .setLocation(
                              RideSearchField.destination,
                              RideLocation(name: d.label, address: d.address),
                            ),
                      ),
                    if (hasCoords) ...[
                      if (estimate.valueOrNull?.any((v) => v.surgeActive) ==
                          true) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          // Every estimate carries the same multiplier, so
                          // reading the first surging option is enough.
                          child: SurgePricingBanner(
                            multiplier: estimate.valueOrNull!
                                .firstWhere((v) => v.surgeActive)
                                .surgeMultiplier,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _VehicleSelectionSection(estimate: estimate),
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
            if (estimateReady)
              _BottomActions(
                // No drivers in range → block the confirm path entirely so the
                // user can't kick off a match that has nobody to match against.
                enabled: selectedOption != null,
                // What the client pays for the selected vehicle — shown bold
                // above the Confirm button. Hidden when no drivers are available
                // (nothing is bookable, so a price would be misleading).
                fareDisplay: selectedOption?.fareDisplay,
                onConfirm: () {
                  // Hand the long-running matcher a container instead of
                  // `ref` — the screen disposes on the next line's `go`,
                  // and `WidgetRef` becomes unusable past the next await.
                  final container =
                      ProviderScope.containerOf(context, listen: false);
                  requestRideAndMatchDriver(
                    container,
                    pretripStops: _bookingStops(ref, multistopEnabled),
                  );
                  context.go(AppRoutes.rideMatching);
                },
                onCancel: () {
                  _resetTripState(ref);
                  context.pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        onPressed: () {
          // Same clean-up as the Cancel button: backing out of Plan Your
          // Trip should not leave stale pickup/destination/vehicle
          // selections behind for the next entry into the flow.
          _resetTripState(ref);
          context.pop();
        },
        icon: const Icon(Icons.arrow_back_rounded,
            color: MyShopColors.textPrimary),
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
}

class _ExactPointNotice extends StatelessWidget {
  const _ExactPointNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MyShopColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: MyShopColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_searching_rounded,
              size: 20, color: MyShopColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is a broad area. Tap the location and choose an exact pin '
              'before we calculate your fare.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
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

class _PreTripStopsSection extends ConsumerWidget {
  const _PreTripStopsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(tripStopsProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'TRIP STOPS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add stops before requesting a driver. Your fare updates with the full route.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: MyShopColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          RouteStopList(
            stops: stops,
            onReorder: (oldIndex, newIndex) =>
                ref.read(tripStopsProvider.notifier).reorder(
                      oldIndex,
                      newIndex,
                    ),
            onRemove: (id) =>
                ref.read(tripStopsProvider.notifier).removeStop(id),
            onEditStop: (stop) => context.push(
              AppRoutes.rideSearchPath('destination'),
              extra: stop.id,
            ),
            onAddStop: () => context.push(
              AppRoutes.rideSearchPath('destination'),
              extra: kNewStopSentinel,
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleSelectionSection extends ConsumerWidget {
  final AsyncValue<List<VehicleOption>> estimate;

  const _VehicleSelectionSection({required this.estimate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedVehicleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Select Vehicle',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        estimate.when(
          loading: () => const _VehicleLoadingSkeleton(),
          error: (error, _) => _VehicleEstimateError(
            error: error,
            onRetry: () => ref.invalidate(fareEstimateProvider),
          ),
          data: (options) {
            final firstAvailable = firstAvailableRideOption(options);
            final noDrivers = options.isNotEmpty && firstAvailable == null;
            // Auto-select the first available option when the current category
            // is absent or unavailable. The confirm button remains disabled
            // until this post-frame state update lands, so booking can never
            // race with a stale unavailable category id.
            if (firstAvailable != null &&
                availableRideOptionById(options, selectedId) == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(selectedVehicleProvider.notifier).state =
                    firstAvailable.id;
              });
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (noDrivers) ...[
                  const _NoDriversBanner(),
                  const SizedBox(height: 12),
                ],
                ...options.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: VehicleOptionCard(
                      option: v,
                      isSelected: selectedId == v.id,
                      onTap: () => ref
                          .read(selectedVehicleProvider.notifier)
                          .state = v.id,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VehicleLoadingSkeleton extends StatelessWidget {
  const _VehicleLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _VehicleEstimateError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _VehicleEstimateError({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final copy = rideEstimateErrorCopy(error);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: copy.showRetry
            ? MyShopColors.errorLight
            : MyShopColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (copy.showRetry ? MyShopColors.error : MyShopColors.warning)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                copy.showRetry
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                size: 20,
                color:
                    copy.showRetry ? MyShopColors.error : MyShopColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  copy.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            copy.message,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: MyShopColors.textSecondary,
            ),
          ),
          if (copy.showRetry) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown above the (disabled) vehicle list when the estimate came back with
/// no driver in range. Spells out the situation in full text so the meaning
/// isn't carried by the grayed-out cards alone (WCAG — not color-only).
class _NoDriversBanner extends StatelessWidget {
  const _NoDriversBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyShopColors.error.withValues(alpha: 0.30)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_off_outlined, size: 18, color: MyShopColors.error),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No drivers available right now',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Every nearby driver is offline or busy. Please try '
                  'again in a few minutes.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSection extends ConsumerWidget {
  const _PaymentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final method = ref.watch(selectedRidePaymentMethodProvider);
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
        PaymentMethodRow(
          method: method,
          onChangeTap: () async {
            final picked = await showRidePaymentMethodSheet(context, method);
            if (picked != null) {
              ref.read(selectedRidePaymentMethodProvider.notifier).state =
                  picked;
            }
          },
        ),
      ],
    );
  }
}

// ── Bottom actions ────────────────────────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool enabled;

  /// Formatted fare for the selected vehicle (e.g. "GHS 23"). When non-null it
  /// renders as a bold "Total to pay" row above the Confirm button.
  final String? fareDisplay;

  const _BottomActions({
    required this.onConfirm,
    required this.onCancel,
    this.enabled = true,
    this.fareDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fareDisplay != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: MyShopColors.primaryGoldLight,
                borderRadius: BorderRadius.circular(MyShopRadius.card),
                border: Border.all(
                  color: MyShopColors.primaryGold.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total to pay',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                  Text(
                    fareDisplay!,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.darkText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              // Null onPressed renders the button in its disabled style — the
              // user can't dispatch a ride when no driver is available.
              onPressed: enabled ? onConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: MyShopColors.textOnPrimary,
                disabledBackgroundColor: MyShopColors.divider,
                disabledForegroundColor: MyShopColors.textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MyShopRadius.button),
                ),
                elevation: 0,
              ),
              child: Text(
                enabled ? 'Confirm Ride' : 'No Drivers Available',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onCancel,
            child: const Text(
              'Cancel Request',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary,
              ),
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
