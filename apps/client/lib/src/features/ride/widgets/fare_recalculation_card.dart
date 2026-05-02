import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/edit_trip_provider.dart';

/// Two-section card:
///   Top — gold "PRICE UPDATE" header with a surge badge on the right.
///   Bottom — white body with original estimate vs new fare + trip deltas.
class FareRecalculationCard extends StatelessWidget {
  final FareRecalculation fare;

  const FareRecalculationCard({super.key, required this.fare});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PriceUpdateHeader(fare: fare),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FareComparison(fare: fare),
                const SizedBox(height: 14),
                _TripDeltas(fare: fare),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top header band — PRICE UPDATE | surge ──────────────────────────────────

class _PriceUpdateHeader extends StatelessWidget {
  final FareRecalculation fare;
  const _PriceUpdateHeader({required this.fare});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MyShopColors.primaryGold,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Text(
            'PRICE UPDATE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (fare.surgeActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                fare.surgeLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Original estimate vs new fare ─────────────────────────────────────────────

class _FareComparison extends StatelessWidget {
  final FareRecalculation fare;
  const _FareComparison({required this.fare});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Original Estimate',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fare.originalFareDisplay,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textSecondary,
                decoration: TextDecoration.lineThrough,
                decorationColor: MyShopColors.textSecondary,
              ),
            ),
          ],
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'New Upfront Fare',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fare.newFareDisplay,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: MyShopColors.textPrimary,
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Time + distance deltas ────────────────────────────────────────────────────

class _TripDeltas extends StatelessWidget {
  final FareRecalculation fare;
  const _TripDeltas({required this.fare});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DeltaChip(
          icon: Icons.access_time_rounded,
          label: '+${fare.extraMinutes} mins travel',
        ),
        const SizedBox(width: 8),
        _DeltaChip(
          icon: Icons.location_on_rounded,
          label: '+${fare.extraKm.toStringAsFixed(1)} km extra',
        ),
      ],
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DeltaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Surge pricing banner (below the card) ────────────────────────────────────

class SurgePricingActiveBanner extends StatelessWidget {
  final FareRecalculation fare;

  const SurgePricingActiveBanner({super.key, required this.fare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt_rounded,
              color: MyShopColors.primaryGold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Surge Pricing Active',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SurgeMultiplierBadge(multiplier: fare.surgeMultiplier),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'High demand in Kumasi. Fares are slightly higher to attract more drivers.',
                  style: TextStyle(
                    fontSize: 11,
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

class _SurgeMultiplierBadge extends StatelessWidget {
  final double multiplier;
  const _SurgeMultiplierBadge({required this.multiplier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGold,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${multiplier.toStringAsFixed(1)}x',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
