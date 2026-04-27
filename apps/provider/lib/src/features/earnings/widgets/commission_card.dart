import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Weekly commission + net-earnings breakdown card.
///
/// Shared between the driver and artisan dashboards. The backend reports
/// `weekCommissionPesewas` directly when it has Payment rows for the user;
/// we fall back to a 20% estimate of the gross when it doesn't (fresh
/// account that hasn't yet earned anything).
class CommissionCard extends StatelessWidget {
  const CommissionCard({
    super.key,
    required this.weekPesewas,
    required this.weekCommissionPesewas,
    required this.weekNetPesewas,
  });

  final int weekPesewas;
  final int weekCommissionPesewas;
  final int weekNetPesewas;

  @override
  Widget build(BuildContext context) {
    final commission = weekCommissionPesewas > 0
        ? weekCommissionPesewas
        : (weekPesewas * 0.20).round();
    final net = weekNetPesewas > 0 ? weekNetPesewas : weekPesewas - commission;

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz,
                  size: 18, color: MyShopColors.textPrimary),
              const SizedBox(width: 6),
              const Text(
                'Commission & Tax',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MyShopColors.divider),
                ),
                child: Text(
                  'Auto-deducted',
                  style: MyShopTypography.body2
                      .copyWith(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          _Row(
            label: 'App Commission (20%)',
            value: '- GHS ${_fmtGhs(commission)}',
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.5, color: MyShopColors.divider),
          const SizedBox(height: 12),
          _Row(
            label: 'Net Earnings',
            value: 'GHS ${_fmtGhs(net)}',
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 14,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
            color: bold
                ? MyShopColors.textPrimary
                : MyShopColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 14,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

String _fmtGhs(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble()) return ghs.toStringAsFixed(0);
  return ghs.toStringAsFixed(2);
}
