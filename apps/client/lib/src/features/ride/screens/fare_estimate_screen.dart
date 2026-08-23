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
import '../widgets/fare_estimate_action_bar.dart';
import '../widgets/route_stop_list.dart';
import '../widgets/surge_pricing_banner.dart';
import '../widgets/vehicle_option_card.dart';

/// PRD 4.3 — Plan Your Trip
///
/// The screen always exposes one persistent next action. Vehicle selection,
/// surge, payment, and the final confirm CTA appear only after both endpoints
/// are exact and the backend returns a bookable fare category.
class FareEstimateScreen extends ConsumerWidget {
  const FareEstimateScreen({super.key});

  /// Clear sticky trip state when the user abandons the screen. Called on
  /// both the back arrow and the Cancel button — without it, the next
  /// visit shows the previous pickup + destination + vehicle, which the
  /// user reads as "the app remembered a trip I already cancelled".
  void _resetTripState(WidgetRef ref) {
    resetRideRequestDraft(ref.read);
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
        .where(
          (s) =>
              s.type == StopType.intermediate && s.lat != null && s.lng != null,
        )
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
    final selectedId = ref.watch(selectedVehicleProvider);
    final actionState = resolveFareEstimateAction(
      search: search,
      estimate: estimate,
      selectedVehicleId: selectedId,
    );

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
                        onDestinationTap: () => context.push(
                          AppRoutes.rideSearchPath('destination'),
                        ),
                        onDestinationPinTap: () => context.push(
                          AppRoutes.ridePinPickerPath('destination'),
                        ),
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
            FareEstimateActionBar(
              state: actionState,
              onPrimary: _primaryAction(
                context,
                ref,
                actionState,
                multistopEnabled: multistopEnabled,
              ),
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

  VoidCallback? _primaryAction(
    BuildContext context,
    WidgetRef ref,
    FareEstimateActionState state, {
    required bool multistopEnabled,
  }) {
    switch (state.action) {
      case FareEstimateAction.choosePickup:
        return () => context.push(AppRoutes.rideSearchPath('pickup'));
      case FareEstimateAction.chooseDestination:
        return () => context.push(AppRoutes.rideSearchPath('destination'));
      case FareEstimateAction.chooseExactPickup:
        return () => context.push(AppRoutes.ridePinPickerPath('pickup'));
      case FareEstimateAction.chooseExactDestination:
        return () => context.push(AppRoutes.ridePinPickerPath('destination'));
      case FareEstimateAction.retryFare:
      case FareEstimateAction.serviceUnavailable:
      case FareEstimateAction.noDrivers:
        return () => ref.invalidate(fareEstimateProvider);
      case FareEstimateAction.changeLocations:
        return () => _showLocationChangeOptions(context);
      case FareEstimateAction.confirm:
        return () {
          final option = state.option;
          if (option == null) return;
          // The action resolver can select the first available category before
          // the post-frame vehicle-card update lands. Persist that exact
          // category synchronously so the request cannot race with stale state.
          ref.read(selectedVehicleProvider.notifier).state = option.id;
          // Hand the long-running matcher a container instead of `ref` — this
          // screen is disposed immediately after navigation.
          final container = ProviderScope.containerOf(context, listen: false);
          requestRideAndMatchDriver(
            container,
            pretripStops: _bookingStops(ref, multistopEnabled),
          );
          context.go(AppRoutes.rideMatching);
        };
      case FareEstimateAction.calculating:
        return null;
    }
  }

  Future<void> _showLocationChangeOptions(BuildContext context) async {
    final field = await showModalBottomSheet<RideSearchField>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Which location would you like to change?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          ListTile(
            key: const Key('change-pickup-location'),
            leading: const Icon(Icons.my_location_rounded),
            title: const Text('Change pickup'),
            onTap: () => Navigator.of(sheetContext).pop(RideSearchField.pickup),
          ),
          ListTile(
            key: const Key('change-destination-location'),
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Change destination'),
            onTap: () =>
                Navigator.of(sheetContext).pop(RideSearchField.destination),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (field == null || !context.mounted) return;
    await context.push(AppRoutes.rideSearchPath(field.name));
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
        icon: const Icon(
          Icons.arrow_back_rounded,
          color: MyShopColors.textPrimary,
        ),
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
        border: Border.all(color: MyShopColors.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_searching_rounded,
            size: 20,
            color: MyShopColors.warning,
          ),
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
            onReorder: (oldIndex, newIndex) => ref
                .read(tripStopsProvider.notifier)
                .reorder(oldIndex, newIndex),
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
        const Text(
          'Select Vehicle',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
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
            VehicleOption? selectedOption;
            for (final option in options) {
              if (option.id == selectedId) {
                selectedOption = option;
                break;
              }
            }
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
                if (selectedOption?.hasToll == true) ...[
                  const SizedBox(height: 4),
                  _SelectedFareBreakdown(option: selectedOption!),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SelectedFareBreakdown extends StatelessWidget {
  const _SelectedFareBreakdown({required this.option});

  final VehicleOption option;

  @override
  Widget build(BuildContext context) {
    final charge = option.toll!;
    return Container(
      key: const Key('selected-fare-breakdown'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FARE BREAKDOWN',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _EstimateAmountRow(
            label: 'Ride fare',
            amount: option.transportFareDisplay,
          ),
          const SizedBox(height: 10),
          _EstimateAmountRow(
            key: const Key('selected-toll-line'),
            label: charge.label,
            amount: 'GH₵ ${(charge.amountPesewas / 100).toStringAsFixed(2)}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: MyShopColors.divider),
          ),
          _EstimateAmountRow(
            label: 'Estimated total',
            amount: option.fareDisplay,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _EstimateAmountRow extends StatelessWidget {
  const _EstimateAmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final weight = emphasized ? FontWeight.w800 : FontWeight.w500;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasized ? 14 : 13,
              fontWeight: weight,
              color: MyShopColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          amount,
          style: TextStyle(
            fontSize: emphasized ? 15 : 13,
            fontWeight: weight,
            color: MyShopColors.textPrimary,
          ),
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
  const _VehicleEstimateError({required this.error, required this.onRetry});

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
