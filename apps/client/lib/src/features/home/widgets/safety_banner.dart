import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

class SafetyBanner extends StatelessWidget {
  const SafetyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.primaryGold, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded,
              color: MyShopColors.primaryGold, size: 26),
          const SizedBox(width: 12),
          const Expanded(child: _BannerText()),
        ],
      ),
    );
  }
}

class _BannerText extends StatelessWidget {
  const _BannerText();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Provider Review Required',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Providers need required documents and Regional Manager approval before going online.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
