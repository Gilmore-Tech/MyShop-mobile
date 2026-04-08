import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// 2×2 grid of quick operation cards.
///
/// Figma: nodes 164:10440 → 164:10492
/// - "QUICK OPERATIONS" header
/// - Cards: MoMo Payout, Shift Summary, Safety Log, Help Line
/// - Each card: 16dp radius, white bg, border, shadow, icon in tinted circle + label
class QuickOperationsGrid extends StatelessWidget {
  const QuickOperationsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK OPERATIONS',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textPrimary,
            letterSpacing: 0.7,
            height: 1.43,
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Row 1
        Row(
          children: [
            Expanded(
              child: _QuickOpCard(
                icon: Icons.credit_card,
                label: 'MOMO PAYOUT',
                iconBgColor: MyShopColors.darkSlate.withValues(alpha: 0.05),
                iconColor: MyShopColors.darkSlate,
                onTap: () {
                  // TODO: Navigate to MoMo payout
                },
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: _QuickOpCard(
                icon: Icons.assignment,
                label: 'SHIFT SUMMARY',
                iconBgColor: MyShopColors.primaryGold.withValues(alpha: 0.1),
                iconColor: MyShopColors.primaryGold,
                onTap: () {
                  // TODO: Navigate to shift summary
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Row 2
        Row(
          children: [
            Expanded(
              child: _QuickOpCard(
                icon: Icons.shield_outlined,
                label: 'SAFETY LOG',
                iconBgColor: MyShopColors.error.withValues(alpha: 0.1),
                iconColor: MyShopColors.error,
                onTap: () {
                  // TODO: Navigate to safety log
                },
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: _QuickOpCard(
                icon: Icons.phone_in_talk,
                label: 'HELP LINE',
                iconBgColor: const Color(0xFFEFF6FF),
                iconColor: MyShopColors.info,
                onTap: () {
                  // TODO: Navigate to help line
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickOpCard extends StatelessWidget {
  const _QuickOpCard({
    required this.icon,
    required this.label,
    required this.iconBgColor,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconBgColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 104,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MyShopColors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12171A1F),
              blurRadius: 2.5,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x14171A1F),
              blurRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(height: 7),

            // Label
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                letterSpacing: 0.28,
                height: 1.27,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
