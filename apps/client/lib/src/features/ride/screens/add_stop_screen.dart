import 'package:api_client/api_client.dart'
    show ApiException, userSafeApiErrorMessage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart' as models;
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../providers/edit_trip_provider.dart';
import '../providers/ride_provider.dart'
    show
        activeRideIdProvider,
        activeRideRouteUpdateProvider,
        applyActiveRideRouteUpdate;
import '../providers/ride_search_provider.dart';
import '../screens/destination_search_screen.dart' show kNewStopSentinel;
import '../utils/ride_destination_change_error.dart';
import '../widgets/fare_recalculation_card.dart';
import '../widgets/route_stop_list.dart';

/// PRD 4.4 — Edit Your Trip / Add Stop Screen
/// Reorder stops, add intermediate stops, view fare recalculation + surge.
class AddStopScreen extends ConsumerStatefulWidget {
  const AddStopScreen({
    super.key,
    this.startWithDestinationSearch = false,
  });

  final bool startWithDestinationSearch;

  @override
  ConsumerState<AddStopScreen> createState() => _AddStopScreenState();
}

class _AddStopScreenState extends ConsumerState<AddStopScreen> {
  bool _submitting = false;
  String? _submitError;
  models.RideDestinationPoint? _originalDestination;
  models.RideDestinationChangePreview? _destinationPreview;
  int _routeRevision = 0;
  String? _commitIdempotencyKey;
  bool _openedInitialDestinationSearch = false;

  @override
  void initState() {
    super.initState();
    // Seed from the rider's actual route. Without this the screen would
    // open with the hardcoded mock stops, and a "Confirm Changes" tap
    // would PATCH bogus addresses to the backend.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _seedStops();
      if (!mounted ||
          !widget.startWithDestinationSearch ||
          _openedInitialDestinationSearch) {
        return;
      }
      final destination = _selectedDestinationStop(ref.read(tripStopsProvider));
      if (destination == null) return;
      _openedInitialDestinationSearch = true;
      await _openSearch(context, stop: destination);
    });
  }

  Future<void> _seedStops() async {
    final rideId = ref.read(activeRideIdProvider);
    if (rideId != null && rideId.isNotEmpty) {
      try {
        final json = await ref.read(rideServiceProvider).getRide(rideId);
        if (!mounted) return;
        final route = models.RideRouteUpdate.fromRideJson(json);
        final stops = (json['stops'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(models.RideStop.fromJson)
                .toList() ??
            const <models.RideStop>[];
        ref.read(tripStopsProvider.notifier).seed(
          pickup: (
            address: json['pickupAddress'] as String?,
            lat: (json['pickupLat'] as num?)?.toDouble(),
            lng: (json['pickupLng'] as num?)?.toDouble(),
          ),
          destination: (
            address: json['dropoffAddress'] as String?,
            lat: (json['dropoffLat'] as num?)?.toDouble(),
            lng: (json['dropoffLng'] as num?)?.toDouble(),
          ),
          existingStops: stops,
        );
        applyActiveRideRouteUpdate(ref.read, route);
        setState(() {
          _originalDestination = route.destination;
          _routeRevision = route.routeRevision;
          _destinationPreview = null;
          _commitIdempotencyKey = null;
        });
        return;
      } catch (_) {
        // Fall through to local search state. The confirm path still requires
        // backend coordinates for newly-added stops, so this fallback only
        // affects what the rider sees before adding a fresh stop.
      }
    }
    if (!mounted) return;
    seedTripStopsFromCurrentRide(ref.read);
    final search = ref.read(rideSearchProvider);
    final destination = search.destination;
    final currentRoute = ref.read(activeRideRouteUpdateProvider);
    if (destination?.hasCoordinates == true) {
      setState(() {
        _originalDestination = models.RideDestinationPoint(
          address: destination!.address,
          lat: destination.lat!,
          lng: destination.lng!,
        );
        _routeRevision = currentRoute?.routeRevision ?? 0;
      });
    }
  }

  Future<void> _submitChanges() async {
    if (_submitting) return;
    final preview = _destinationPreview;
    if (preview != null) {
      await _confirmDestinationChange(preview);
      return;
    }

    final stops = ref.read(tripStopsProvider);
    final destination = _selectedDestination(stops);
    if (_destinationChanged(destination)) {
      if (stops.any((stop) => stop.isPendingNewStop)) {
        setState(() {
          _submitError = 'Confirm the destination separately from new stops. '
              'Remove the pending stop, change the destination, then add the stop.';
        });
        return;
      }
      await _previewDestinationChange(destination);
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final notifier = ref.read(tripStopsProvider.notifier);
      final submitted = await notifier.submitNewStopsToBackend();
      if (!mounted) return;
      // No new stops = the rider only reordered or hit Confirm without
      // adding anything; either way pop with `true` so the caller knows
      // the user committed (the backend is authoritative on order so
      // there's nothing else to do for a pure reorder right now).
      Navigator.of(context).pop(submitted >= 0);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitError = _friendlyError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitError = "Couldn't add the stop. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  models.RideDestinationPoint? _selectedDestination(List<TripStop> stops) {
    final row = _selectedDestinationStop(stops);
    if (row?.lat == null || row?.lng == null || row!.address.trim().isEmpty) {
      return null;
    }
    return models.RideDestinationPoint(
      address: row.address.trim(),
      lat: row.lat!,
      lng: row.lng!,
    );
  }

  TripStop? _selectedDestinationStop(List<TripStop> stops) {
    return stops.cast<TripStop?>().firstWhere(
          (stop) => stop?.type == StopType.destination,
          orElse: () => null,
        );
  }

  bool _destinationChanged(models.RideDestinationPoint? selected) {
    final original = _originalDestination;
    if (selected == null || original == null) return false;
    return (selected.lat - original.lat).abs() > 0.000001 ||
        (selected.lng - original.lng).abs() > 0.000001 ||
        selected.address.trim() != original.address.trim();
  }

  Future<void> _previewDestinationChange(
    models.RideDestinationPoint? destination,
  ) async {
    final rideId = ref.read(activeRideIdProvider);
    if (rideId == null || rideId.isEmpty || destination == null) {
      setState(() {
        _submitError = 'Choose an exact destination before reviewing the fare.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final preview =
          await ref.read(rideServiceProvider).previewDestinationChange(
                rideId,
                destination: destination,
                expectedRouteRevision: _routeRevision,
              );
      if (!mounted) return;
      if (preview.rideId != rideId || preview.routeRevision != _routeRevision) {
        throw const FormatException('Preview route revision mismatch');
      }
      setState(() {
        _destinationPreview = preview;
        _commitIdempotencyKey = const Uuid().v4();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _submitError = friendlyRideDestinationChangeError(error),
      );
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _submitError = 'The route changed while the fare was being reviewed. '
            'Refresh and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't calculate the new fare. Please try again.";
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmDestinationChange(
    models.RideDestinationChangePreview preview,
  ) async {
    final rideId = ref.read(activeRideIdProvider);
    if (rideId == null || rideId != preview.rideId) return;
    if (preview.tokenIsExpired) {
      setState(() {
        _destinationPreview = null;
        _commitIdempotencyKey = null;
        _submitError = 'The fare preview expired. Review the fare again.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final update =
          await ref.read(rideServiceProvider).confirmDestinationChange(
                rideId,
                confirmationToken: preview.confirmationToken,
                expectedRouteRevision: preview.routeRevision,
                idempotencyKey: _commitIdempotencyKey ?? const Uuid().v4(),
              );
      if (update.rideId != rideId ||
          update.routeRevision <= preview.routeRevision ||
          !update.hasCompleteRouteProjection) {
        throw const FormatException('Invalid destination commit response');
      }
      if (!mounted) return;
      applyActiveRideRouteUpdate(ref.read, update);
      final destination = update.destination!;
      ref.read(tripStopsProvider.notifier).updateStopAddress(
            'destination',
            destination.address,
            lat: destination.lat,
            lng: destination.lng,
          );
      _originalDestination = destination;
      _routeRevision = update.routeRevision;
      _destinationPreview = null;
      _commitIdempotencyKey = null;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = friendlyRideDestinationChangeError(error);
        if (destinationPreviewNoLongerUsable(error.errorCode)) {
          _destinationPreview = null;
          _commitIdempotencyKey = null;
        }
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _destinationPreview = null;
        _commitIdempotencyKey = null;
        _submitError = 'The route changed before confirmation. '
            'Review the updated fare again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't change the destination. Please try again.";
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'INVALID_STATUS_TRANSITION':
      case 'RIDE_NOT_ACTIVE':
        return "You can't add stops once the trip has finished.";
      case 'STOP_OUT_OF_PILOT_REGION':
        return 'That location is outside the pilot service area.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: "Couldn't add the stop. Please try again.",
          conflictMessage:
              'The ride changed before the stop was added. Refresh and try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = ref.watch(tripStopsProvider);
    final selectedDestination = _selectedDestination(stops);
    final destinationChanged = _destinationChanged(selectedDestination);
    final preview = _destinationPreview;
    final fare = preview == null
        ? null
        : FareRecalculation.fromDestinationPreview(preview);
    final currentFare = ref.watch(fareRecalculationProvider);
    final pendingStops = stops.where((stop) => stop.isPendingNewStop).length;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── YOUR ROUTE ───────────────────────────────────────────
                const _SectionHeader(
                  title: 'YOUR ROUTE',
                  trailing: 'Add stops before confirming',
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RouteStopList(
                    stops: stops,
                    onReorder: (old, next) =>
                        ref.read(tripStopsProvider.notifier).reorder(old, next),
                    onRemove: (id) =>
                        ref.read(tripStopsProvider.notifier).removeStop(id),
                    onEditStop: (stop) => _openSearch(context, stop: stop),
                    onAddStop: () =>
                        _openSearch(context, addingIntermediate: true),
                    allowDestinationEditing: true,
                  ),
                ),
                const SizedBox(height: 20),
                // ── FARE RECALCULATION ───────────────────────────────────
                const _SectionHeader(title: 'FARE RECALCULATION'),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: fare != null && preview != null
                      ? Column(
                          children: [
                            _DestinationComparison(preview: preview),
                            const SizedBox(height: 10),
                            FareRecalculationCard(fare: fare),
                          ],
                        )
                      : _FareUpdateNotice(
                          currentFareDisplay: currentFare.originalFareDisplay,
                          destinationChanged: destinationChanged,
                        ),
                ),
                if (fare?.surgeActive == true) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SurgePricingActiveBanner(fare: fare!),
                  ),
                ],
                const SizedBox(height: 20),
                // ── FARE SUMMARY (original + difference) ─────────────────
                if (fare != null) _FareSummaryRow(fare: fare),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _submitError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MyShopColors.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Sticky footer: Confirm Changes + Discard link
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _StickyFooter(
              isSubmitting: _submitting,
              label: _submitting
                  ? (preview == null ? 'Calculating fare…' : 'Changing…')
                  : preview != null
                      ? 'Confirm New Fare'
                      : destinationChanged
                          ? 'Review Fare Change'
                          : pendingStops > 0
                              ? 'Confirm Added Stops'
                              : 'Done',
              onConfirm: _submitChanges,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_rounded,
            color: MyShopColors.textPrimary),
      ),
      centerTitle: false,
      title: const Text(
        'Edit Your Trip',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: MyShopColors.successLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'In-Progress',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MyShopColors.success,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Pushes the destination search screen (same flow as the pickup/destination
  /// inputs on the fare-estimate screen). Either:
  ///   - [stop]: editing an existing stop (pickup / intermediate / destination)
  ///   - [addingIntermediate]: creating a new intermediate stop
  /// When the user picks a place (or drops a pin via the screen's "Set
  /// location on map" action) the selection writes back to tripStopsProvider.
  Future<void> _openSearch(
    BuildContext context, {
    TripStop? stop,
    bool addingIntermediate = false,
  }) async {
    // Pickup and persisted intermediate-stop editing are deliberately not
    // surfaced: neither has an authoritative backend mutation contract.
    if (stop?.type == StopType.pickup ||
        (stop?.type == StopType.intermediate &&
            stop?.isPendingNewStop != true)) {
      return;
    }
    const fieldArg = 'destination';
    final extra = addingIntermediate ? kNewStopSentinel : stop?.id;
    await context.push(AppRoutes.rideSearchPath(fieldArg), extra: extra);
    if (!mounted) return;
    setState(() {
      _destinationPreview = null;
      _commitIdempotencyKey = null;
      _submitError = null;
    });
  }
}

class _DestinationComparison extends StatelessWidget {
  const _DestinationComparison({required this.preview});

  final models.RideDestinationChangePreview preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          _DestinationRow(
            label: 'CURRENT DESTINATION',
            address: preview.oldDestination.address,
            muted: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          _DestinationRow(
            label: 'NEW DESTINATION',
            address: preview.newDestination.address,
          ),
        ],
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.label,
    required this.address,
    this.muted = false,
  });

  final String label;
  final String address;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          muted ? Icons.location_on_outlined : Icons.location_on_rounded,
          size: 20,
          color: muted ? MyShopColors.textSecondary : MyShopColors.primaryGold,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                address,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: muted
                      ? MyShopColors.textSecondary
                      : MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FareUpdateNotice extends StatelessWidget {
  const _FareUpdateNotice({
    required this.currentFareDisplay,
    required this.destinationChanged,
  });

  final String currentFareDisplay;
  final bool destinationChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 20, color: MyShopColors.primaryGold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              destinationChanged
                  ? 'Your destination is not changed yet. Tap “Review Fare '
                      'Change” to see the exact new fare, distance and time '
                      'before confirming.'
                  : 'Current fare is $currentFareDisplay. Add a stop or tap '
                      'the destination to make a route change.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
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

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
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
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
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

// ── Fare summary row (original + difference) ──────────────────────────────────

class _FareSummaryRow extends StatelessWidget {
  final FareRecalculation fare;
  const _FareSummaryRow({required this.fare});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'Original Fare: ${fare.originalFareDisplay}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: MyShopColors.textSecondary,
            ),
          ),
          const Spacer(),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              children: [
                const TextSpan(
                  text: 'Difference: ',
                  style: TextStyle(color: MyShopColors.textSecondary),
                ),
                TextSpan(
                  text: fare.differenceDisplay,
                  style: const TextStyle(color: MyShopColors.primaryGold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky footer: Confirm + Discard ─────────────────────────────────────────

class _StickyFooter extends StatelessWidget {
  final bool isSubmitting;
  final String label;
  final VoidCallback onConfirm;
  const _StickyFooter({
    required this.isSubmitting,
    required this.label,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MyShopPrimaryButton(
            label: label,
            trailingIcon: Icons.chevron_right_rounded,
            onPressed: isSubmitting ? null : onConfirm,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: isSubmitting ? null : () => context.pop(false),
            child: const Text(
              'Discard & Return to Map',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
