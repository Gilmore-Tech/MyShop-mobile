import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shared layout used by every step in the provider registration wizard.
///
/// Renders the app bar, stepper header, per-step heading, and sticky
/// Back/Continue footer. The [child] slot is given the remaining vertical
/// space between the heading and the footer — typically a `PageView` —
/// so individual steps can host their own scroll views.
class RegistrationStepScaffold extends StatelessWidget {
  const RegistrationStepScaffold({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onContinue,
    required this.continueLabel,
    required this.isContinueEnabled,
    this.onBack,
    this.onAppBarBack,
    this.isSubmitting = false,
    this.errorText,
  });

  final List<MyShopStepItem> steps;
  final int currentIndex;
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback onContinue;
  final String continueLabel;
  final bool isContinueEnabled;

  /// Footer "Back" button. When `null` the button is hidden (step 0).
  final VoidCallback? onBack;

  /// Called when the AppBar leading arrow is tapped. Defaults to
  /// `Navigator.maybePop`.
  final VoidCallback? onAppBarBack;

  final bool isSubmitting;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: MyShopColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: onAppBarBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create Account', style: MyShopTypography.h3),
            Text(
              'Complete the steps to get started',
              style: MyShopTypography.body2,
            ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: MyShopSpacing.md),
            MyShopStepper(steps: steps, currentIndex: currentIndex),
            const SizedBox(height: MyShopSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.lg,
              ),
              child: _StepHeader(title: title, subtitle: subtitle),
            ),
            const SizedBox(height: MyShopSpacing.md),
            Expanded(child: child),
            _Footer(
              onBack: onBack,
              onContinue: onContinue,
              continueLabel: continueLabel,
              isContinueEnabled: isContinueEnabled,
              isSubmitting: isSubmitting,
              errorText: errorText,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a step body in the gold-bordered scrollable card used on every step.
class RegistrationStepCard extends StatelessWidget {
  const RegistrationStepCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.lg,
        0,
        MyShopSpacing.lg,
        MyShopSpacing.md,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: MyShopColors.offWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        padding: const EdgeInsets.all(MyShopSpacing.md),
        child: child,
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: MyShopTypography.h1),
        const SizedBox(height: MyShopSpacing.xs),
        Text(subtitle, style: MyShopTypography.body2),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.onBack,
    required this.onContinue,
    required this.continueLabel,
    required this.isContinueEnabled,
    required this.isSubmitting,
    required this.errorText,
  });

  final VoidCallback? onBack;
  final VoidCallback onContinue;
  final String continueLabel;
  final bool isContinueEnabled;
  final bool isSubmitting;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.lg,
        MyShopSpacing.md,
        MyShopSpacing.lg,
        MyShopSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorText != null) ...[
            Text(
              errorText!,
              textAlign: TextAlign.center,
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),
          ],
          Row(
            children: [
              if (onBack != null) ...[
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: isSubmitting ? null : onBack,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyShopColors.textPrimary,
                        side: const BorderSide(color: MyShopColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Back',
                        style: MyShopTypography.button.copyWith(
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: MyShopSpacing.md),
              ],
              Expanded(
                child: MyShopPrimaryButton(
                  label: continueLabel,
                  isLoading: isSubmitting,
                  onPressed: !isSubmitting ? onContinue : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
