import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_radius.dart';
import '../theme/myshop_spacing.dart';
import '../theme/myshop_typography.dart';

/// Full-screen error state with retry button.
///
/// Drop-in replacement for the per-screen `_ErrorBody` widgets that were
/// duplicated across 9+ screens.
///
/// Usage inside an `AsyncValue.when(error:)` callback:
/// ```dart
/// error: (_, __) => MyShopErrorBody(
///   message: 'Could not load bid details',
///   onRetry: () => ref.invalidate(bidDetailProvider(bidId)),
/// ),
/// ```
class MyShopErrorBody extends StatelessWidget {
  const MyShopErrorBody({
    super.key,
    required this.message,
    required this.onRetry,
    this.subtitle = 'Check your connection and try again.',
    this.icon = Icons.error_outline_rounded,
    this.retryLabel = 'Try Again',
  });

  final String message;
  final VoidCallback onRetry;
  final String subtitle;
  final IconData icon;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: MyShopColors.textHint),
            const SizedBox(height: MyShopSpacing.lg),
            Text(
              message,
              style: MyShopTypography.h3.copyWith(
                color: MyShopColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              subtitle,
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MyShopSpacing.lg),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(MyShopRadius.button),
                ),
                child: Text(
                  retryLabel,
                  style: MyShopTypography.button.copyWith(
                    color: MyShopColors.surfaceWhite,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
