import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../data/earnings_service.dart';
import '../providers/earnings_providers.dart';

/// Recent payouts list backed by [payoutsProvider]. The underlying
/// `/payments/payouts` endpoint is role-agnostic — backend filters by the
/// authenticated user's role — so this widget is shared between the driver
/// and artisan earnings screens.
class PayoutsList extends ConsumerWidget {
  const PayoutsList({super.key, this.maxRows = 5});

  final int maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payouts = ref.watch(payoutsProvider);
    return payouts.when(
      loading: () => const _PayoutsEmpty(
        title: 'Loading payouts…',
        subtitle: 'Fetching the most recent transfers',
      ),
      error: (_, __) => const _PayoutsEmpty(
        title: "Couldn't load payouts",
        subtitle: 'Pull down to retry',
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const _PayoutsEmpty(
            title: 'No payouts yet',
            subtitle: 'Your payout history will appear here',
          );
        }
        return Column(
          children: [
            for (final row in rows.take(maxRows))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PayoutRow(payout: row),
              ),
          ],
        );
      },
    );
  }
}

class _PayoutsEmpty extends StatelessWidget {
  const _PayoutsEmpty({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.history,
                size: 20, color: MyShopColors.textSecondary),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            title,
            style:
                MyShopTypography.body1.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: MyShopSpacing.xs),
          Text(
            subtitle,
            style: MyShopTypography.body2
                .copyWith(color: MyShopColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout});

  final DriverPayout payout;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatDate(payout.createdAt);
    final statusColor = _statusColor(payout.status);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smartphone,
                size: 18, color: MyShopColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _methodLabel(payout.method),
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: MyShopTypography.body2.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                payout.amountDisplay,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                payout.status.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'success':
      case 'succeeded':
      case 'completed':
        return MyShopColors.success;
      case 'failed':
      case 'declined':
        return MyShopColors.error;
      default:
        return MyShopColors.textSecondary;
    }
  }

  static String _methodLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'momo':
      case 'mobile_money':
      case 'momo_mtn':
        return 'MTN MoMo';
      case 'momo_telecel':
        return 'Telecel Cash';
      case 'momo_airteltigo':
        return 'AirtelTigo Money';
      case 'card':
        return 'Card payout';
      case 'bank':
        return 'Bank transfer';
      default:
        return raw.isEmpty ? 'Payout' : raw;
    }
  }

  static String _formatDate(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} · $hh:$mm';
  }
}
