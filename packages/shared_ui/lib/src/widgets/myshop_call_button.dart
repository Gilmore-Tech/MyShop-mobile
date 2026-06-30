import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../utils/phone_dialer.dart';

/// Compact circular "call" affordance that opens the dialer for [phoneNumber].
///
/// Mirrors the 44×44 rounded-square treatment used by the in-app chat buttons
/// so the two peer-contact actions sit side by side consistently. Renders
/// nothing when [phoneNumber] is null/empty — callers don't need to guard the
/// visibility themselves.
class MyShopCallButton extends StatelessWidget {
  const MyShopCallButton({
    super.key,
    required this.phoneNumber,
    this.size = 44,
    this.color = MyShopColors.success,
    this.semanticLabel = 'Call',
  });

  final String? phoneNumber;
  final double size;
  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final number = phoneNumber?.trim() ?? '';
    if (number.isEmpty) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () => dialPhoneNumber(context, number),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(size * 0.27),
          ),
          child: Icon(
            Icons.call_rounded,
            size: size * 0.45,
            color: MyShopColors.textOnPrimary,
          ),
        ),
      ),
    );
  }
}
