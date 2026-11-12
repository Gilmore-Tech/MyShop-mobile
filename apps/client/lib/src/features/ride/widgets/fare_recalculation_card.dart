import 'package:flutter/material.dart';
import 'surge_price_indicator.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/edit_trip_provider.dart';

/// Two-section card:
///   Top — gold "PRICE UPDATE" header.
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
          const _PriceUpdateHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FareComparison(fare: fare),
                const SizedBox(height: 14),
                _TripDeltas(fare: fare),
                if (fare.promo?.applies == true) ...[
                  const SizedBox(height: 12),
                  _PricingDetailRow(
                    label: fare.promo?.label ?? 'Promo retained',
                    value:
                        '-GH₵ ${(fare.promo!.discountPesewas / 100).toStringAsFixed(2)}',
                  ),
                ],
                if (fare.toll != null) ...[
                  const SizedBox(height: 8),
                  _PricingDetailRow(
                    label: fare.toll!.label,
                    value: fare.toll!.amountDisplay,
                  ),
                ],
                if (fare.remoteAreaAdjustment != null) ...[
                  const SizedBox(height: 8),
                  _PricingDetailRow(
                    label: fare.remoteAreaAdjustment!.label,
                    value:
                        'GH₵ ${(fare.remoteAreaAdjustment!.amountPesewas / 100).toStringAsFixed(2)}',
                  ),
                ],
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
  const _PriceUpdateHeader();

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
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                fare.newFareDisplay,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textPrimary,
                  height: 1.1,
                ),
              ),
              if (fare.surgeActive) ...[
                const SizedBox(width: 4),
                SurgePriceIndicator(multiplier: fare.surgeMultiplier),
              ],
            ]),
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
          label: '${fare.displayedDurationMins} mins projected',
        ),
        const SizedBox(width: 8),
        _DeltaChip(
          icon: Icons.location_on_rounded,
          label: '${fare.displayedDistanceKm.toStringAsFixed(1)} km projected',
        ),
      ],
    );
  }
}

class _PricingDetailRow extends StatelessWidget {
  const _PricingDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
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
