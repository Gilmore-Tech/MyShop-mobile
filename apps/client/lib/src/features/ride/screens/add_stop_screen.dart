import 'package:api_client/api_client.dart' show ApiException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../providers/edit_trip_provider.dart';
import '../screens/destination_search_screen.dart' show kNewStopSentinel;
import '../widgets/fare_recalculation_card.dart';
import '../widgets/route_stop_list.dart';

/// PRD 4.4 — Edit Your Trip / Add Stop Screen
/// Reorder stops, add intermediate stops, view fare recalculation + surge.
class AddStopScreen extends ConsumerStatefulWidget {
  const AddStopScreen({super.key});

  @override
  ConsumerState<AddStopScreen> createState() => _AddStopScreenState();
}

class _AddStopScreenState extends ConsumerState<AddStopScreen> {
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    // Seed from the rider's actual route. Without this the screen would
    // open with the hardcoded mock stops, and a "Confirm Changes" tap
    // would PATCH bogus addresses to the backend.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      seedTripStopsFromCurrentRide(ref.read);
    });
  }

  Future<void> _submitChanges() async {
    if (_submitting) return;
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
      setState(() =>
          _submitError = "Couldn't add the stop. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'INVALID_STATUS_TRANSITION':
        return "You can't add stops once the trip has finished.";
      case 'STOP_OUT_OF_PILOT_REGION':
        return 'That location is outside the pilot service area.';
      default:
        return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = ref.watch(tripStopsProvider);
    final fare = ref.watch(fareRecalculationProvider);

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
                  trailing: 'Drag to reorder',
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RouteStopList(
                    stops: stops,
                    onReorder: (old, next) => ref
                        .read(tripStopsProvider.notifier)
                        .reorder(old, next),
                    onRemove: (id) =>
                        ref.read(tripStopsProvider.notifier).removeStop(id),
                    onEditStop: (stop) => _openSearch(context, stop: stop),
                    onAddStop: () => _openSearch(context, addingIntermediate: true),
                  ),
                ),
                const SizedBox(height: 20),
                // ── FARE RECALCULATION ───────────────────────────────────
                const _SectionHeader(title: 'FARE RECALCULATION'),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FareRecalculationCard(fare: fare),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SurgePricingActiveBanner(fare: fare),
                ),
                const SizedBox(height: 20),
                // ── FARE SUMMARY (original + difference) ─────────────────
                _FareSummaryRow(fare: fare),
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
              fare: fare,
              isSubmitting: _submitting,
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
        icon: const Icon(Icons.arrow_back_rounded, color: MyShopColors.textPrimary),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
  void _openSearch(
    BuildContext context, {
    TripStop? stop,
    bool addingIntermediate = false,
  }) {
    final fieldArg = (stop?.type == StopType.pickup) ? 'pickup' : 'destination';
    final extra = addingIntermediate ? kNewStopSentinel : stop?.id;
    context.push(AppRoutes.rideSearchPath(fieldArg), extra: extra);
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
  final FareRecalculation fare;
  final bool isSubmitting;
  final VoidCallback onConfirm;
  const _StickyFooter({
    required this.fare,
    required this.isSubmitting,
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
            label: isSubmitting ? 'Adding stop…' : 'Confirm Changes',
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

