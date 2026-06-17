import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../domain/loyalty_models.dart';
import '../providers/loyalty_redemption_providers.dart';
import 'redeem_points_sheet.dart';

/// Reusable entry point for loyalty redemption on an active booking.
///
/// Renders one of three states:
///   • nothing — when the client has no points and hasn't redeemed;
///   • a tappable "Apply loyalty points" row — when points are available and
///     none have been applied yet (opens [RedeemPointsSheet]);
///   • a non-interactive "Loyalty discount applied" line — once redeemed
///     (one redemption per booking, so the control is disabled afterward).
///
/// Drop it straight into the ride active-fare sheet and the artisan-job
/// payment screen — [bookingType] is the only thing that differs.
class ApplyLoyaltyPointsRow extends ConsumerWidget {
  const ApplyLoyaltyPointsRow({
    super.key,
    required this.bookingType,
    required this.bookingId,
    required this.farePesewas,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final RedeemableBookingType bookingType;
  final String bookingId;
  final int farePesewas;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applied = ref.watch(appliedRedemptionProvider(bookingId));
    final balance = ref.watch(loyaltyBalanceProvider);

    if (applied != null) {
      return Padding(
        padding: padding,
        child: _AppliedLine(redemption: applied),
      );
    }

    // Nothing to offer — hide the row entirely rather than show a dead control.
    if (balance <= 0) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Semantics(
        button: true,
        label: 'Apply loyalty points. You have $balance points.',
        child: InkWell(
          onTap: () => showRedeemPointsSheet(
            context: context,
            bookingType: bookingType,
            bookingId: bookingId,
            farePesewas: farePesewas,
          ),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: MyShopColors.primaryGold.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.redeem_rounded,
                    color: MyShopColors.primaryGold, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Apply loyalty points',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$balance ${balance == 1 ? 'point' : 'points'} available '
                        'for a fare discount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: MyShopColors.primaryGold, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppliedLine extends StatelessWidget {
  const _AppliedLine({required this.redemption});

  final LoyaltyRedemption redemption;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${redemption.pointsRedeemed} loyalty points applied, '
          'you saved ${redemption.discountDisplay}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MyShopColors.successLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: MyShopColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Loyalty discount applied · ${redemption.pointsRedeemed} pts',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.success,
                ),
              ),
            ),
            Text(
              '-${redemption.discountDisplay}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: MyShopColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
