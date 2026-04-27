import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/ride_payment_method_provider.dart';

/// Inline row showing the rider's selected payment method on the fare
/// estimate (and any future ride-confirmation surfaces). Reads the icon
/// and label off the [RidePaymentMethod] enum so adding a method only
/// requires extending the enum, not touching this widget.
class PaymentMethodRow extends StatelessWidget {
  final RidePaymentMethod method;
  final VoidCallback? onChangeTap;

  const PaymentMethodRow({
    super.key,
    required this.method,
    this.onChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MethodIcon(method: method),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            method.label,
            style: const TextStyle(
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

class _MethodIcon extends StatelessWidget {
  const _MethodIcon({required this.method});

  final RidePaymentMethod method;

  @override
  Widget build(BuildContext context) {
    if (method == RidePaymentMethod.momoMtn) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: MyShopColors.mtnYellow,
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
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        method.icon,
        size: 18,
        color: MyShopColors.textPrimary,
      ),
    );
  }
}
