import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Centered confirmation dialog shown after the artisan submits a bid.
///
/// PRD Reference: PRD 5.3 — bid acknowledgement / escrow notification.
class BidConfirmationModal extends StatelessWidget {
  const BidConfirmationModal({
    super.key,
    required this.clientFirstName,
    required this.bidAmount,
    required this.arrivalEta,
  });

  final String clientFirstName;
  final num bidAmount;
  final String arrivalEta;

  static Future<void> show(
    BuildContext context, {
    required String clientFirstName,
    required num bidAmount,
    required String arrivalEta,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Bid confirmation',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: BidConfirmationModal(
                clientFirstName: clientFirstName,
                bidAmount: bidAmount,
                arrivalEta: arrivalEta,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.lg),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success check badge
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: MyShopColors.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 40,
                  color: MyShopColors.success,
                ),
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // Title
            Text(
              'Confirmation Sent!',
              textAlign: TextAlign.center,
              style: MyShopTypography.h2.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),

            // Subtitle
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
                children: [
                  const TextSpan(text: "We've notified "),
                  TextSpan(
                    text: clientFirstName,
                    style: const TextStyle(
                      color: MyShopColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(text: " that you've accepted the request."),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // Bid summary card
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: MyShopSpacing.md,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.offWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'YOUR BID',
                          style: MyShopTypography.overline.copyWith(
                            color: MyShopColors.textSecondary,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Text(
                        'GH₵ ${bidAmount.toStringAsFixed(2)}',
                        style: MyShopTypography.h3.copyWith(
                          color: MyShopColors.primaryGold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ARRIVAL ETA',
                          style: MyShopTypography.overline.copyWith(
                            color: MyShopColors.textSecondary,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Text(
                        arrivalEta,
                        style: MyShopTypography.h3.copyWith(
                          color: MyShopColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // Got it button
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Got it, thanks!',
                  style: MyShopTypography.button.copyWith(
                    color: MyShopColors.textOnDarkSlate,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // Helper
            Text(
              'Payment is held securely and released after job completion.',
              textAlign: TextAlign.center,
              style: MyShopTypography.body2.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
