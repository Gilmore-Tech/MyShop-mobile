import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

class PaymentMethodRow extends StatelessWidget {
  final VoidCallback? onChangeTap;

  const PaymentMethodRow({super.key, this.onChangeTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MtnIcon(),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'MTN Mobile Money',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
          ),
        ),
        GestureDetector(
          onTap: onChangeTap,
          child: const Text(
            'Change',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MyShopColors.primaryGold,
            ),
          ),
        ),
      ],
    );
  }
}

class _MtnIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: MyShopColors.mtnYellow, // MTN yellow
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'M',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
