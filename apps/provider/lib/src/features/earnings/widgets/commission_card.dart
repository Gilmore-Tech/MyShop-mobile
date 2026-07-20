import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Commission + net-earnings breakdown card.
///
/// Shared between the driver and artisan dashboards. Driven by the report
/// endpoint's `grossEarningsPesewas` / `commissionChargedPesewas` /
/// `netEarningsPesewas` for whatever window the caller chose (defaults to
/// the week).
class CommissionCard extends StatelessWidget {
  const CommissionCard({
    super.key,
    required this.grossPesewas,
    required this.commissionPesewas,
    required this.netPesewas,
    this.title = 'Commission & Tax',
  });

  /// Gross revenue for the window (pre-commission, includes cash + in-app).
  final int grossPesewas;

  /// Commission already deducted by the backend.
  final int commissionPesewas;

  /// Net take-home (gross minus commission). Trusts the backend — no
  /// fallback subtraction here, which used to double-deduct the commission
  /// whenever the backend reported a real value.
  final int netPesewas;

  final String title;

  @override
  Widget build(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.swap_horiz,
                  size: 18, color: MyShopColors.textPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
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
            label: 'Gross Revenue',
            value: 'GHS ${_fmtGhs(grossPesewas)}',
          ),
          const SizedBox(height: 12),
          _Row(
            label: 'App Commission',
            value: '- GHS ${_fmtGhs(commissionPesewas)}',
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 0.5, color: MyShopColors.divider),
          const SizedBox(height: 12),
          _Row(
            label: 'Net Earnings',
            value: 'GHS ${_fmtGhs(netPesewas)}',
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 14,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
              color:
                  bold ? MyShopColors.textPrimary : MyShopColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: MyShopSpacing.sm),
        Text(
          value,
          textAlign: TextAlign.end,
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
