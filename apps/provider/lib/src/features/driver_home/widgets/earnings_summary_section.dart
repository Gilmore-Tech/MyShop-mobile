import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../earnings/providers/earnings_providers.dart';

/// Today's earnings section inside the draggable sheet.
///
/// Figma: nodes 164:10411 → 164:10428
/// - "TODAY'S EARNINGS" overline label
/// - Large "GHS 482.50" price
/// - Horizontal stats row: Trips | Hours | Tips (separated by vertical lines)
///
/// Backed by `GET /payments/earnings/today-card?role=driver`. Hours are
/// active trip time only (per backend handoff §3.1) — NOT online idle time.
class EarningsSummarySection extends ConsumerWidget {
  const EarningsSummarySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(todayCardProvider(EarningsRole.driver));

    return cardAsync.when(
      loading: () => const _EarningsSkeleton(),
      error: (_, __) => const Padding(
        padding: EdgeInsets.all(MyShopSpacing.md),
        child: Center(
          child: Text(
            'Could not load earnings',
            style: MyShopTypography.body2,
          ),
        ),
      ),
      data: (card) => Padding(
        padding: const EdgeInsets.fromLTRB(
          MyShopSpacing.md,
          MyShopSpacing.lg,
          MyShopSpacing.md,
          MyShopSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            Text(
              'TODAY\'S EARNINGS',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textSecondary,
                letterSpacing: 1.1,
                height: 1.55,
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),

            // Amount
            Text(
              'GH₵ ${_formatAmount(card.netEarningsPesewas)}',
              style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textPrimary,
                letterSpacing: -0.9,
                height: 1.11,
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // Stats row with dividers
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: MyShopColors.divider, width: 0.5),
                  bottom: BorderSide(color: MyShopColors.divider, width: 0.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _StatColumn(
                      label: 'TRIPS',
                      value: '${card.bookingsCount}',
                    ),
                    const _VerticalDivider(),
                    _StatColumn(
                      label: 'HOURS',
                      value: _formatMinutes(card.hoursWorkedMinutes),
                    ),
                    const _VerticalDivider(),
                    _StatColumn(
                      label: 'TIPS',
                      value: 'GH₵ ${_formatAmount(card.tipsEarnedPesewas)}',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatAmount(int pesewas) {
    final ghs = pesewas / 100;
    if (ghs == ghs.truncateToDouble()) {
      return ghs.toStringAsFixed(0);
    }
    return ghs.toStringAsFixed(2);
  }

  /// Formats backend's `hoursWorkedMinutes` (active trip time only). Renders
  /// "3h 35m" / "45m" / "2h" depending on magnitude.
  static String _formatMinutes(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 47,
      color: MyShopColors.divider,
    );
  }
}

class _EarningsSkeleton extends StatelessWidget {
  const _EarningsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(120, 11),
          const SizedBox(height: MyShopSpacing.sm),
          _shimmerBox(200, 36),
          const SizedBox(height: MyShopSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (_) {
              return Column(
                children: [
                  _shimmerBox(40, 10),
                  const SizedBox(height: 4),
                  _shimmerBox(50, 20),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: MyShopColors.shimmerBase,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
