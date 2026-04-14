import 'package:flutter/material.dart';
import '../providers/edit_trip_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _goldLight = Color(0xFFFFF8EC);
const _warning = Color(0xFFF2994A);
const _warningLight = Color(0xFFFEF3E8);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _border = Color(0xFFE0E0E0);

class FareRecalculationCard extends StatelessWidget {
  final FareRecalculation fare;

  const FareRecalculationCard({super.key, required this.fare});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _goldLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _BadgeRow(fare: fare),
          const SizedBox(height: 14),
          _FareComparison(fare: fare),
          const SizedBox(height: 12),
          _TripDeltas(fare: fare),
        ],
      ),
    );
  }
}

// ── Badge row: PRICE UPDATE + Surge Active ────────────────────────────────────

class _BadgeRow extends StatelessWidget {
  final FareRecalculation fare;
  const _BadgeRow({required this.fare});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PillBadge(
          label: 'PRICE UPDATE',
          bgColor: _gold,
          textColor: Colors.white,
        ),
        const SizedBox(width: 8),
        if (fare.surgeActive)
          _PillBadge(
            label: fare.surgeLabel,
            bgColor: _warning,
            textColor: Colors.white,
          ),
      ],
    );
  }
}

class _PillBadge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _PillBadge({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: 0.4,
        ),
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
        // Left: original (greyed out, smaller)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Original Estimate',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fare.originalFareDisplay,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
                decoration: TextDecoration.lineThrough,
                decorationColor: _textSecondary,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Right: new fare (large bold)
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'New Upfront Fare',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fare.newFareDisplay,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
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
        const SizedBox(width: 12),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
      ],
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
        color: _goldLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt_rounded, color: _gold, size: 20),
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
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SurgeMultiplierBadge(
                        multiplier: fare.surgeMultiplier),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'High demand in Kumasi. Fares are slightly higher to attract more drivers.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
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
        color: _warning,
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
