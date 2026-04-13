import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/verification_provider.dart';

/// Shows a bottom sheet listing the incomplete profile items that prevent
/// the provider from going online.
///
/// Call this when the user tries to toggle online but their profile is
/// not fully verified.
void showIncompleteProfileSheet(
  BuildContext context, {
  required ProfileCompletion completion,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _IncompleteProfileSheet(
      completion: completion,
      onGoToAccount: () {
        Navigator.of(context).pop();
        context.go('/account');
      },
    ),
  );
}

class _IncompleteProfileSheet extends StatelessWidget {
  const _IncompleteProfileSheet({
    required this.completion,
    required this.onGoToAccount,
  });

  final ProfileCompletion completion;
  final VoidCallback onGoToAccount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MyShopSpacing.lg,
            MyShopSpacing.md,
            MyShopSpacing.lg,
            MyShopSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MyShopColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // Icon + title
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: MyShopColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: MyShopColors.warning,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: MyShopSpacing.sm),
                  Expanded(
                    child: Text(
                      'Complete your profile to go online',
                      style: MyShopTypography.h3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MyShopSpacing.sm),
              Text(
                'You need to complete the following before you can start '
                'receiving requests:',
                style: MyShopTypography.body2,
              ),
              const SizedBox(height: MyShopSpacing.md),

              // Missing items
              ...completion.missing.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: MyShopColors.error.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: MyShopColors.error,
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      Expanded(
                        child: Text(
                          item,
                          style: MyShopTypography.body1.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: MyShopSpacing.sm),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: completion.progress,
                  minHeight: 6,
                  backgroundColor: MyShopColors.surfaceGrey,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    completion.percentage >= 80
                        ? MyShopColors.success
                        : completion.percentage >= 50
                            ? MyShopColors.warning
                            : MyShopColors.error,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${completion.percentage}% complete '
                '(${completion.completed} of ${completion.total})',
                style: MyShopTypography.caption,
              ),

              const SizedBox(height: MyShopSpacing.lg),

              // CTA
              SizedBox(
                width: double.infinity,
                child: MyShopPrimaryButton(
                  label: 'Go to Account',
                  onPressed: onGoToAccount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
