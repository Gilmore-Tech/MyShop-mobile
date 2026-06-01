import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/payment_provider.dart';

/// Modal bottom sheet the client uses to pick how they want to settle a
/// completed job. Two options:
///
///   - In-app  → opens the Paystack hosted checkout
///   - Cash    → notifies the artisan; artisan confirms receipt in their app
///
/// Returns the chosen [PaymentMethod], or null if the user dismissed the
/// sheet.
Future<PaymentMethod?> showPaymentMethodSheet(BuildContext context) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _PaymentMethodSheet(),
  );
}

class _PaymentMethodSheet extends StatelessWidget {
  const _PaymentMethodSheet();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        w * 0.051,
        MyShopSpacing.sm,
        w * 0.051,
        bottomPad + MyShopSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Text(
            'How would you like to pay?',
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.006),
          Text(
            'Pay securely through Paystack or settle directly in cash with '
            'the artisan.',
            style: TextStyle(
              fontSize: w * 0.031,
              color: MyShopColors.textSecondary,
              height: 1.4,
            ),
          ),
          SizedBox(height: h * 0.020),
          _MethodCard(
            icon: Icons.phone_android_rounded,
            title: 'Pay in-app',
            subtitle: "Instant MoMo or card via Paystack. Funds held in "
                'escrow until the job is confirmed.',
            // Defaults to MTN Mobile Money — user can switch to Telecel,
            // AirtelTigo, Visa, or Mastercard on the payment screen.
            onTap: () => Navigator.of(context).pop(PaymentMethod.momoMtn),
          ),
          SizedBox(height: h * 0.012),
          _MethodCard(
            icon: Icons.payments_outlined,
            title: 'Pay with cash',
            subtitle: "We'll ask the artisan to confirm they received the "
                'cash before marking the job complete.',
            onTap: () => Navigator.of(context).pop(PaymentMethod.cash),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.118,
              height: w * 0.118,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: MyShopColors.primaryGold, size: 24),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: w * 0.041,
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: w * 0.028,
                      color: MyShopColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: MyShopColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
