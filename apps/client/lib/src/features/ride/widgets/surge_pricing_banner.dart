import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

const _warningBg = MyShopColors.primaryGoldLight; // primaryGoldLight

class SurgePricingBanner extends StatelessWidget {
  /// Raw multiplier from the backend (e.g. 1.3 for a 30% surge). Pass it
  /// in so the banner can render the actual rate — a generic "surge is
  /// on" notice that doesn't tell the user HOW much higher fares are is
  /// the kind of warning that erodes pricing trust over time.
  final double multiplier;

  const SurgePricingBanner({super.key, required this.multiplier});

  @override
  Widget build(BuildContext context) {
    // e.g. 1.30 → "1.3×" — clean one-decimal display.
    // final pct = ((multiplier - 1) * 100).round();
    final rate = multiplier.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _warningBg,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.4)),
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
                    Text(
                      'Surge Pricing Active · $rate×',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LiveBadge(),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'High demand in your area currently',
                  style: const TextStyle(
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

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGold,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
