import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

class RideSafetyBanner extends StatelessWidget {
  const RideSafetyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.shield_outlined, size: 18, color: MyShopColors.primaryGold),
          ),
          const SizedBox(width: 10),
          const Expanded(child: _SafetyText()),
        ],
      ),
    );
  }
}

class _SafetyText extends StatelessWidget {
  const _SafetyText();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: MyShopColors.textSecondary,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: 'Safety First: ',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text:
                'Please verify the vehicle plate and driver identity before entering the car. '
                'Share your trip status with friends.',
          ),
        ],
      ),
    );
  }
}
