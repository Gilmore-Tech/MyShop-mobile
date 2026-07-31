import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/ride_provider.dart';
import '../providers/ride_search_provider.dart';
import '../utils/ride_error_messages.dart';

enum FareEstimateAction {
  choosePickup,
  chooseDestination,
  chooseExactPickup,
  chooseExactDestination,
  calculating,
  retryFare,
  changeLocations,
  serviceUnavailable,
  noDrivers,
  confirm,
}

class FareEstimateActionState {
  const FareEstimateActionState({
    required this.action,
    required this.title,
    required this.message,
    required this.primaryLabel,
    this.option,
  });

  final FareEstimateAction action;
  final String title;
  final String message;
  final String primaryLabel;
  final VehicleOption? option;

  bool get isBusy => action == FareEstimateAction.calculating;
  bool get canConfirm => action == FareEstimateAction.confirm && option != null;
}

/// Produces one explicit next step for every state of the fare request.
///
/// This is deliberately independent of the visual widget so tests can prove
/// that pickup/destination selection never lands the rider on a dead-end
/// screen. Backend fare, geofence, availability, and matching decisions remain
/// authoritative.
FareEstimateActionState resolveFareEstimateAction({
  required RideSearchState search,
  required AsyncValue<List<VehicleOption>> estimate,
  required String selectedVehicleId,
}) {
  final pickup = search.pickup;
  final destination = search.destination;

  if (pickup == null) {
    return const FareEstimateActionState(
      action: FareEstimateAction.choosePickup,
      title: 'Choose your pickup',
      message: 'Select where the driver should meet you.',
      primaryLabel: 'Choose Pickup',
    );
  }
  if (destination == null) {
    return const FareEstimateActionState(
      action: FareEstimateAction.chooseDestination,
      title: 'Choose your destination',
      message: 'Select where you want to go.',
      primaryLabel: 'Choose Destination',
    );
  }
  if (!pickup.isPrecise) {
    return const FareEstimateActionState(
      action: FareEstimateAction.chooseExactPickup,
      title: 'Confirm your exact pickup',
      message:
          'Move the map pin to the exact place the driver should meet you.',
      primaryLabel: 'Choose Exact Pickup',
    );
  }
  if (!destination.isPrecise) {
    return const FareEstimateActionState(
      action: FareEstimateAction.chooseExactDestination,
      title: 'Confirm your exact destination',
      message:
          'Move the map pin to your exact destination before we price the ride.',
      primaryLabel: 'Choose Exact Destination',
    );
  }

  if (estimate.isLoading) {
    return const FareEstimateActionState(
      action: FareEstimateAction.calculating,
      title: 'Calculating your fare',
      message: 'Checking ride options and nearby driver availability.',
      primaryLabel: 'Calculating Fare…',
    );
  }

  if (estimate.hasError) {
    final error = estimate.error!;
    final copy = rideEstimateErrorCopy(error);
    if (isOutsideRideServiceAreaError(error)) {
      return FareEstimateActionState(
        action: FareEstimateAction.changeLocations,
        title: copy.title,
        message: copy.message,
        primaryLabel: 'Change Locations',
      );
    }
    if (error is NetworkException) {
      return FareEstimateActionState(
        action: FareEstimateAction.retryFare,
        title: copy.title,
        message: copy.message,
        primaryLabel: 'Retry Fare Estimate',
      );
    }
    return FareEstimateActionState(
      action: FareEstimateAction.serviceUnavailable,
      title: 'Fare service unavailable',
      message: copy.message,
      primaryLabel: 'Retry Fare Estimate',
    );
  }

  final options = estimate.valueOrNull ?? const <VehicleOption>[];
  if (options.isEmpty) {
    return const FareEstimateActionState(
      action: FareEstimateAction.serviceUnavailable,
      title: 'No ride options available',
      message:
          'We could not load a ride option for this trip. Please try again.',
      primaryLabel: 'Retry Fare Estimate',
    );
  }

  final selected = availableRideOptionById(options, selectedVehicleId) ??
      firstAvailableRideOption(options);
  if (selected == null) {
    return const FareEstimateActionState(
      action: FareEstimateAction.noDrivers,
      title: 'No drivers available right now',
      message:
          'Every nearby driver is offline or busy. Try again in a moment or change your locations.',
      primaryLabel: 'Try Again',
    );
  }

  return FareEstimateActionState(
    action: FareEstimateAction.confirm,
    title: 'Ready to request',
    message: 'Review your trip and fare before requesting a driver.',
    primaryLabel: 'Confirm Ride',
    option: selected,
  );
}

class FareEstimateActionBar extends StatelessWidget {
  const FareEstimateActionBar({
    super.key,
    required this.state,
    required this.onPrimary,
    required this.onCancel,
  });

  final FareEstimateActionState state;
  final VoidCallback? onPrimary;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return Material(
      key: const Key('fare-estimate-bottom-action'),
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        state.message,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.option?.fareDisplay case final fare?) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      fare,
                      textAlign: TextAlign.end,
                      maxLines: textScaler.scale(16) > 28 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.darkSlate,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: ElevatedButton(
                key: const Key('fare-estimate-primary-action'),
                onPressed: state.isBusy ? null : onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.darkSlate,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: MyShopColors.divider,
                  disabledForegroundColor: MyShopColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (state.isBusy) ...[
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        state.primaryLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            TextButton(
              key: const Key('fare-estimate-cancel-action'),
              onPressed: onCancel,
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
      ),
    );
  }
}
