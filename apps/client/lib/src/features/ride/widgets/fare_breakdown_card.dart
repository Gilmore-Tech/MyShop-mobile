import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/ride_provider.dart';

class FareBreakdownCard extends StatelessWidget {
  final MatchedDriver driver;

  const FareBreakdownCard({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FareRow(label: 'Base Fare', amount: driver.baseFareDisplay),
          const SizedBox(height: 10),
          _FareRow(
            label: 'Distance (${driver.distanceKm.toStringAsFixed(1)} km)',
            amount: driver.distanceFareDisplay,
          ),
          const SizedBox(height: 10),
          _FareRow(label: 'Booking Fee', amount: driver.bookingFeeDisplay),
          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          const SizedBox(height: 14),
          _TotalRow(total: driver.totalFareDisplay),
          const SizedBox(height: 8),
          const Text(
            'Includes all taxes and commissions. No hidden charges.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label;
  final String amount;

  const _FareRow({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          amount,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String total;
  const _TotalRow({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Total Upfront Fare',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        const Spacer(),
        Text(
          total,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
