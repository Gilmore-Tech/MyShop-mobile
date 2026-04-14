import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/edit_trip_provider.dart';
import '../widgets/fare_recalculation_card.dart';
import '../widgets/route_stop_list.dart';

// Design tokens
const _offWhite = Color(0xFFF6F7F8);
const _gold = Color(0xFFF5A623);
const _success = Color(0xFF27AE60);
const _successLight = Color(0xFFE8F8EF);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _error = Color(0xFFEB5757);
const _divider = Color(0xFFE0E0E0);

/// PRD 4.4 — Edit Your Trip / Add Stop Screen
/// Reorder stops, add intermediate stops, view fare recalculation with surge notice.
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── YOUR ROUTE ───────────────────────────────────────────
                _SectionHeader(
                  title: 'YOUR ROUTE',
                  trailing: 'Drag to reorder',
                ),
                Container(
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1, thickness: 1, color: _divider),
                      RouteStopList(
                        stops: stops,
                        onReorder: (old, next) => ref
                            .read(tripStopsProvider.notifier)
                            .reorder(old, next),
                        onRemove: (id) =>
                            ref.read(tripStopsProvider.notifier).removeStop(id),
                        onAddStop: () => _showAddStopDialog(context, ref),
                      ),
                      const Divider(height: 1, thickness: 1, color: _divider),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // ── FARE RECALCULATION ───────────────────────────────────
                _SectionHeader(title: 'FARE RECALCULATION'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FareRecalculationCard(fare: fare),
                      // SOS button overlapping top-right of card
                      Positioned(
                        right: -6,
                        top: -6,
                        child: _SosChip(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SurgePricingActiveBanner(fare: fare),
                ),
                const SizedBox(height: 24),
                // ── FARE SUMMARY + ACTIONS ───────────────────────────────
                _FareSummaryRow(fare: fare),
                const SizedBox(height: 120), // Bottom padding for sticky footer
              ],
            ),
          ),
          // Sticky bottom actions
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
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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

  void _showAddStopDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Add Stop',
          style: TextStyle(fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter stop address',
            hintStyle: const TextStyle(color: Color(0xFFBDBDBD)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _gold),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(tripStopsProvider.notifier)
                    .addIntermediateStop(controller.text.trim());
              }
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Add Stop'),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

// ── SOS chip (overlapping card) ───────────────────────────────────────────────

class _SosChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _error,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _error.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'SOS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.4,
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _textPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
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
            onTap: () => Navigator.of(context).pop(false),
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
