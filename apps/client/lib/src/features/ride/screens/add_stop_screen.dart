import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/edit_trip_provider.dart';
import '../screens/destination_search_screen.dart' show kNewStopSentinel;
import '../widgets/fare_recalculation_card.dart';
import '../widgets/route_stop_list.dart';

// Design tokens
const _offWhite = Color(0xFFF6F7F8);
const _gold = Color(0xFFF5A623);
const _success = Color(0xFF27AE60);
const _successLight = Color(0xFFE8F8EF);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);

/// PRD 4.4 — Edit Your Trip / Add Stop Screen
/// Reorder stops, add intermediate stops, view fare recalculation + surge.
class AddStopScreen extends ConsumerWidget {
  const AddStopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(tripStopsProvider);
    final fare = ref.watch(fareRecalculationProvider);

    return Scaffold(
      backgroundColor: _offWhite,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 160),
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
              ],
            ),
          ),
          // Sticky footer: Confirm Changes + Discard link
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _StickyFooter(fare: fare),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_rounded, color: _textPrimary),
      ),
      title: const Text(
        'Edit Your Trip',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: _textPrimary,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _successLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'In-Progress',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _success,
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
              color: _textSecondary,
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
                color: _textSecondary,
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
              color: _textSecondary,
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
                  style: TextStyle(color: _textSecondary),
                ),
                TextSpan(
                  text: fare.differenceDisplay,
                  style: const TextStyle(color: _gold),
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
  const _StickyFooter({required this.fare});

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
            // Theme supplies the dark-slate background; no override needed.
            child: ElevatedButton(
              onPressed: () => context.pop(true),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Confirm Changes',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => context.pop(false),
            child: const Text(
              'Discard & Return to Map',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

